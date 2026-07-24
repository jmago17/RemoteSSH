import Foundation
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

    init() {
        #if DEBUG
        TestSeed.applyIfRequested()
        #endif
        self.config = store.loadConfig()
        self.pollInterval = store.pollInterval
    }

    var isConfigured: Bool {
        config.isComplete && store.hasStoredSecret(for: config)
    }

    // MARK: Config

    func reloadConfig() {
        config = store.loadConfig()
        pollInterval = store.pollInterval
        restartNotifications()
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

        do {
            let fetched = try await tmux.fetchSessions(config: config, credential: credential)
            sessions = applyUnread(to: fetched)
            errorMessage = nil
        } catch {
            errorMessage = friendly(error)
        }
    }

    /// Marks a session read (call when the user opens its thread).
    func markRead(_ name: String) {
        if let session = sessions.first(where: { $0.name == name }) {
            lastSeenHash[name] = session.contentHash
        }
        if let idx = sessions.firstIndex(where: { $0.name == name }) {
            sessions[idx].hasUnread = false
        }
    }

    // MARK: Actions

    func kill(_ name: String) async {
        await mutate { tmux, config, credential in
            try await tmux.killSession(name, config: config, credential: credential)
        }
    }

    func rename(_ name: String, to newName: String) async {
        await mutate { tmux, config, credential in
            try await tmux.renameSession(name, to: newName, config: config, credential: credential)
        }
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
