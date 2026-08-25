import Foundation
import UserNotifications
import Observation

/// Drives the session list: foreground polling, unread detection, and the
/// mutating actions (kill / rename). Runs on the main actor so the views can
/// read its state directly.
@MainActor
@Observable
final class SessionListModel {
    var sessions: [TmuxSession] = []
    var isRefreshing = false
    var errorMessage: String?

    var config: SSHConnectionConfig
    var pollInterval: TimeInterval

    /// Set when a notification/deep-link asks to open a session; the list view
    /// observes this and navigates.
    var pendingOpenSession: String?

    /// The session currently open in the terminal — the pushed screen at
    /// compact width, the detail column at regular width. Held as a *name*
    /// rather than a `TmuxSession` so it survives the poll that replaces every
    /// session value (preview and hash change every few seconds).
    var selectedSessionName: String?

    /// Set by the app to deliver an ntfy "needs attention" message as an iOS
    /// notification (session name, body).
    @ObservationIgnored var onAttention: ((String, String) -> Void)?

    /// Set by the app to request iOS notification permission.
    @ObservationIgnored var onRequestNotificationAuth: (() -> Void)?

    func requestNotificationAuthorization() {
        onRequestNotificationAuth?()
    }

    private let store = SettingsStore()
    private let tmux = TmuxService()
    private let ntfy = NtfySubscriber()
    private var pollTask: Task<Void, Never>?

    /// Last pane hash the user has actually seen, per session name.
    private var lastSeenHash: [String: Int] = [:]

    /// All saved hosts (for the host switcher).
    var hosts: [SSHConnectionConfig] = []

    init() {
        self.config = store.activeConfig()
        self.pollInterval = store.pollInterval
        self.hosts = store.loadHosts()
    }

    var isConfigured: Bool {
        config.isComplete && store.hasStoredSecret(for: config)
    }

    // MARK: Config / hosts

    func reloadConfig() {
        hosts = store.loadHosts()
        config = store.activeConfig()
        pollInterval = store.pollInterval
        restartNotifications()
    }

    private var cloudObserver: (any NSObjectProtocol)?

    /// Starts iCloud Key-Value sync: pulls the latest, and reloads whenever
    /// another device changes settings.
    func startCloudSync() {
        store.migrateCredentialsToSyncIfNeeded()
        NSUbiquitousKeyValueStore.default.synchronize()
        guard cloudObserver == nil else { return }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.store.mirrorFromCloud()
                self.reloadConfig()
                await self.refresh()
            }
        }
    }

    /// Switches the active host and refreshes immediately.
    func selectHost(_ id: UUID) {
        store.activeHostID = id
        reloadConfig()
        sessions = []
        lastSeenHash = [:]
        selectedSessionName = nil
        Task { await refresh() }
    }

    /// Adds or updates a host; optionally stores a new secret and makes it active.
    func saveHost(_ config: SSHConnectionConfig, secret: String?, makeActive: Bool) {
        store.upsertHost(config)
        if let secret, !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? store.saveSecret(secret, for: config)
        }
        if makeActive { store.activeHostID = config.id }
        reloadConfig()
        if makeActive { Task { await refresh() } }
    }

    func deleteHost(_ id: UUID) {
        store.deleteHost(id)
        reloadConfig()
    }

    func hasSecret(for config: SSHConnectionConfig) -> Bool {
        store.hasStoredSecret(for: config)
    }

    // MARK: Wake

    /// Broadcasts a Wake-on-LAN packet to the active host, then retries the poll.
    func wakeOnLAN() {
        guard config.canWakeOnLAN, let mac = config.macAddress else { return }
        let host = config.host
        Task.detached { WakeOnLAN.wake(macAddress: mac, host: host) }
        errorMessage = "Sent wake signal to \(config.name). Waiting for \(config.host) to come up…"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            await self?.refresh()
        }
    }

    /// Wakes the Mac's display via `caffeinate` (requires an existing connection).
    func wakeDisplay() async {
        guard let credential = store.loadCredential(for: config) else { return }
        do {
            try await tmux.wakeDisplay(config: config, credential: credential)
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: Notifications

    /// Opens a session from a notification tap or `remotessh://open/<name>` link.
    func requestOpen(_ name: String) {
        pendingOpenSession = name
    }

    /// (Re)subscribes to the ntfy topic if notifications are enabled.
    func restartNotifications() {
        let enabled = store.notificationsEnabled
        let server = store.ntfyServer
        let topic = store.ntfyTopic
        let onMessage: @Sendable (String, String) -> Void = { [weak self] session, body in
            Task { @MainActor in self?.onAttention?(session, body) }
        }
        Task { [ntfy] in
            if enabled, !topic.isEmpty {
                await ntfy.start(server: server, topic: topic, onMessage: onMessage)
            } else {
                await ntfy.stop()
            }
        }
    }

    // MARK: Polling lifecycle

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                let interval = self.pollInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        // A refresh interrupted mid-flight never runs its own `defer`, so this
        // flag would stay true and leave the UI spinning for good. See
        // `SessionListView`'s scenePhase handling for when that happens.
        isRefreshing = false
    }

    // MARK: Refresh

    func refresh() async {
        guard isConfigured else {
            errorMessage = nil
            sessions = []
            return
        }
        guard let credential = store.loadCredential(for: config) else {
            errorMessage = "No stored credential for this connection."
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        // Ask whether anything is listening before trying to talk to it. A
        // sleeping Mac now costs ~1.5s instead of the SSH connect timeout, and
        // the two failures stop looking alike: "nothing is there" is a
        // different problem, with a different fix, from "SSH turned us away".
        //
        // The session list is deliberately left alone rather than cleared —
        // the Mac going to sleep doesn't mean those sessions are gone, and
        // blanking the screen every time the laptop lid shuts would lose the
        // last thing the user was looking at.
        guard await HostReachability.canReach(host: config.host, port: config.port) else {
            errorMessage = "\(config.host) isn't answering on port \(config.port). It's probably asleep or off."
            return
        }

        do {
            let fetched = try await tmux.fetchSessions(config: config, credential: credential)
            sessions = applyUnread(to: fetched)
            refreshBadge()
            errorMessage = nil
        } catch {
            errorMessage = friendly(error)
        }
    }

    /// Marks a session read (call when the user opens its thread).
    /// Puts the unread count on the app icon.
    ///
    /// **What this can and cannot do.** It only runs while the app is running,
    /// because the badge number lives in the push payload otherwise — and the
    /// push provider in use (Brrr) doesn't expose a `badge` field at all. So
    /// the badge is right whenever the app has looked recently, and goes stale
    /// while the app is closed. Making it light up the moment an agent
    /// finishes needs APNs of our own, which is a different piece of work.
    ///
    /// Still worth having on its own: it survives leaving the app with unread
    /// sessions, which is the case where a dismissed notification would
    /// otherwise leave no trace at all.
    private func refreshBadge() {
        let count = sessions.filter(\.hasUnread).count
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }

    func markRead(_ name: String) {
        if let session = sessions.first(where: { $0.name == name }) {
            lastSeenHash[name] = session.contentHash
        }
        if let idx = sessions.firstIndex(where: { $0.name == name }) {
            sessions[idx].hasUnread = false
            refreshBadge()
        }
    }

    // MARK: Actions

    func kill(_ name: String) async {
        await mutate { tmux, config, credential in
            try await tmux.killSession(name, config: config, credential: credential)
        }
        // The detail column would otherwise keep a pane open on a session that
        // no longer exists.
        if selectedSessionName == name { selectedSessionName = nil }
    }

    func rename(_ name: String, to newName: String) async {
        await mutate { tmux, config, credential in
            try await tmux.renameSession(name, to: newName, config: config, credential: credential)
        }
        if selectedSessionName == name { selectedSessionName = newName }
    }

    func createSession(_ name: String) async {
        await mutate { tmux, config, credential in
            try await tmux.createSession(name, config: config, credential: credential)
        }
    }

    /// Restores saved tmux sessions via tmux-resurrect, then refreshes.
    func restoreSessions() async {
        guard let credential = store.loadCredential(for: config) else { return }
        do {
            let restored = try await tmux.restoreSessions(config: config, credential: credential)
            if restored {
                await refresh()
            } else {
                errorMessage = "tmux-resurrect isn't installed on \(config.host). Install it to restore saved sessions."
            }
        } catch {
            errorMessage = friendly(error)
        }
    }

    private func mutate(
        _ body: (TmuxService, SSHConnectionConfig, SSHCredential) async throws -> Void
    ) async {
        guard let credential = store.loadCredential(for: config) else { return }
        do {
            try await body(tmux, config, credential)
            await refresh()
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: Helpers

    private func applyUnread(to fetched: [TmuxSession]) -> [TmuxSession] {
        fetched.map { session in
            var s = session
            if let seen = lastSeenHash[s.name] {
                s.hasUnread = seen != s.contentHash
            } else {
                // First time we see this session — baseline it, no unread dot.
                lastSeenHash[s.name] = s.contentHash
                s.hasUnread = false
            }
            return s
        }
    }

    private func friendly(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
