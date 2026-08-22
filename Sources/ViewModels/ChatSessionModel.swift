import Foundation
import Observation
import CryptoKit

/// Drives one session's conversational view: pulls the pane, parses it into
/// turns, and sends commands back.
///
/// Deliberately separate from `SessionListModel` — that one owns the list and
/// its polling; this one is created per open session and dies with the screen.
/// It opens its own short-lived SSH connections, which is fine: each
/// `RemoteShell` lives and dies inside one `withShell` call, so a capture
/// running alongside the list's poll shares no state with it.
@MainActor
@Observable
final class ChatSessionModel {
    let sessionName: String

    private(set) var transcript = Transcript(turns: [], fallback: nil)
    /// True only for the very first load, so a refresh doesn't blank the view.
    private(set) var isLoadingInitial = true
    private(set) var isRefreshing = false
    private(set) var isSending = false
    private(set) var errorMessage: String?

    /// The AI-generated recap of what Claude Code just concluded. Populated
    /// whenever a fresh, not-yet-summarised conclusion is idle in the pane —
    /// including on the very first `refresh()` of a screen that just opened
    /// on an already-idle session, which is the common case. `nil` before
    /// anything has been summarised, cleared again the moment a new command
    /// starts.
    private(set) var conclusionSummary: ClaudeCodeSummariser.ConclusionSummary?
    private(set) var isSummarising = false
    private(set) var summaryError: String?

    /// What the user is typing in the composer.
    var draft = ""

    /// Commands sent from this screen, newest last — used to repopulate the
    /// composer, and to keep the just-sent command visible while the pane
    /// catches up.
    private(set) var pendingCommand: String?

    private let config: SSHConnectionConfig
    private let store = SettingsStore()
    private let tmux = TmuxService()

    /// How much scrollback to ask for. 2000 lines is what `captureScrollback`
    /// has always defaulted to and is plenty for a reading view.
    private let scrollbackLines = 2000

    /// Live-updates the banner while Claude Code is working. `ChatScreen` has
    /// no equivalent of `SessionListModel`'s list poller — without this, a
    /// command that finishes between manual refreshes (returning from the
    /// terminal, reopening the screen) shows stale "working" state until the
    /// user does something that happens to trigger a reload.
    private var pollTask: Task<Void, Never>?

    init(sessionName: String, config: SSHConnectionConfig) {
        self.sessionName = sessionName
        self.config = config
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// True when there's genuinely nothing to show — not merely "still loading".
    var isEmpty: Bool {
        transcript.turns.isEmpty && !isLoadingInitial && errorMessage == nil
    }

    // MARK: Loading

    /// Captures the pane and re-parses it. Safe to call repeatedly — notably
    /// when returning from the real terminal, where the user has probably just
    /// run something.
    func refresh() async {
        guard let credential = store.loadCredential(for: config) else {
            errorMessage = "No stored credential for this connection."
            isLoadingInitial = false
            return
        }
        guard !isRefreshing else { return }

        isRefreshing = true
        defer {
            isRefreshing = false
            isLoadingInitial = false
        }

        do {
            let snapshot = try await tmux.capturePane(
                session: sessionName,
                lines: scrollbackLines,
                config: config,
                credential: credential
            )
            // Parsing a couple of thousand lines is real work; `parsed` is
            // `@concurrent`, so it happens off the main actor and only the
            // finished value comes back here.
            let parsed = await TranscriptParser.parsed(snapshot)
            transcript = parsed
            errorMessage = nil
            pendingCommand = nil
            // Warm the on-device model now, while Claude Code is still busy
            // and nobody is waiting on us. By the time there's a conclusion to
            // summarise, model load and instruction prefill are already paid.
            if case .working = parsed.claudeCode?.activity {
                ClaudeCodeSummariser.prepare()
            }
            summariseIfNewConclusion(parsed.claudeCode?.activity)
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: Claude Code — live status + conclusion summary

    /// How often to re-read the pane while Claude Code is working. Fast,
    /// because this is what keeps the banner's elapsed time and verb honest.
    private static let workingPollInterval = Duration.seconds(4)

    /// How often to re-read it while Claude Code is idle or waiting on an
    /// answer. Slower, but NOT never — see `startWatchingClaudeCode`.
    private static let restingPollInterval = Duration.seconds(15)

    /// Starts a light poll to keep the Claude Code banner honest.
    ///
    /// This used to skip the round trip entirely unless the pane was already
    /// `.working`, on the assumption that an idle session has nothing that
    /// changes between the user's own refreshes. That assumption is wrong, and
    /// wrong in the direction that matters: **it made the idle -> working
    /// transition invisible**. Claude Code starts working for reasons this app
    /// never sees - the user typing on the Mac, a hook, a subagent - and once
    /// the banner said idle, nothing ever looked again. The only way back to
    /// "working" was to send a command from the app or return from the
    /// terminal, i.e. exactly the cases that already refresh on their own.
    ///
    /// So it now always polls, just at two speeds. Ordinary shells (no Claude
    /// Code in the pane) still cost nothing: there is no banner to keep honest.
    ///
    /// Call when the screen appears; `stopWatching` cancels it when the screen
    /// goes away (leaving one poller alive per open chat screen would multiply
    /// SSH round trips for no benefit once the user has navigated elsewhere).
    func startWatchingClaudeCode() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.pollInterval ?? Self.restingPollInterval
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                // An ordinary shell has no banner to keep honest, so it keeps
                // the old deal: no polling at all.
                guard self.transcript.claudeCode != nil else { continue }
                await self.refresh()
            }
        }
    }

    private var pollInterval: Duration {
        if case .working = transcript.claudeCode?.activity {
            return Self.workingPollInterval
        }
        return Self.restingPollInterval
    }

    func stopWatchingClaudeCode() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Fires the summary when Claude Code is idle *and* its conclusion hasn't
    /// already been summarised. A content digest — not a working→idle edge —
    /// is the right test: the edge only fires if the app was open and this
    /// exact `ChatSessionModel` instance witnessed the transition, so opening
    /// the app after Claude Code finished unattended (the actual common case)
    /// never triggered anything. A persisted digest instead answers "have I
    /// summarised *this text* already", which is true whether the user saw
    /// the transition, missed it, or the app was relaunched entirely.
    private func summariseIfNewConclusion(_ activity: ClaudeCodeStatus.Activity?) {
        guard case .idle = activity else {
            // A fresh command invalidates whatever the last summary was about.
            if case .working = activity, conclusionSummary != nil {
                conclusionSummary = nil
                summaryError = nil
            }
            return
        }
        guard !isSummarising,
              let conclusion = ClaudeCodeRecogniser.lastConclusion(text: transcript.turns.first?.text ?? "")
        else { return }

        let digest = Self.digest(of: conclusion)
        if digest == Self.lastSummarisedDigest(for: sessionName) {
            // Already summarised this exact conclusion — but if the app was
            // relaunched since, conclusionSummary starts nil and the card
            // would otherwise vanish on every reopen of an already-seen
            // session. Restore the cached card instead of regenerating it:
            // FoundationModels isn't deterministic, so regenerating would
            // also silently change the wording each time, which reads as a
            // bug, not as "nothing new happened".
            if conclusionSummary == nil {
                conclusionSummary = Self.cachedSummary(for: sessionName)
            }
            return
        }

        Task { [weak self] in await self?.summarise(conclusion, digest: digest) }
    }

    private func summarise(_ conclusion: String, digest: String) async {
        isSummarising = true
        summaryError = nil
        defer { isSummarising = false }
        do {
            let summary = try await ClaudeCodeSummariser.summarise(conclusion) { [weak self] partial in
                // Show the headline the moment it exists rather than holding
                // the whole card back for the last bullet. `isSummarising`
                // stays true, so the card keeps its in-progress marker.
                self?.conclusionSummary = partial
            }
            conclusionSummary = summary
            // Persisted only on success: if this failed (Apple Intelligence
            // still downloading, device unsupported), the next refresh must
            // retry rather than remember a failure as "already summarised".
            Self.saveSummarisedDigest(digest, summary: summary, for: sessionName)
        } catch {
            // Clears any partial the stream had already delivered: half a
            // summary presented as finished is exactly the "confident and
            // wrong" failure this whole feature is built to avoid.
            conclusionSummary = nil
            summaryError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Digest persistence (device-local, deliberately NOT SettingsStore)

    /// "Have I already summarised this session's current conclusion" is a
    /// per-device cache fact, not a user preference — it must not sync via
    /// iCloud KVS (two devices legitimately want independent state here,
    /// same as `HostKeyValidator`'s TOFU trust, which uses this same plain
    /// `UserDefaults.standard` pattern rather than `SettingsStore`).
    ///
    /// Swift's `Hasher` is seeded per-process — `hashValue` on a String is
    /// **not stable across launches** and must never be persisted. SHA-256
    /// is the deterministic equivalent.
    private static func digest(of text: String) -> String {
        let normalised = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return SHA256.hash(data: Data(normalised.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func digestKey(for session: String) -> String { "claudeConclusionDigest.\(session)" }
    private static func summaryKey(for session: String) -> String { "claudeConclusionSummary.\(session)" }

    private static func lastSummarisedDigest(for session: String) -> String? {
        UserDefaults.standard.string(forKey: digestKey(for: session))
    }

    private static func cachedSummary(for session: String) -> ClaudeCodeSummariser.ConclusionSummary? {
        guard let data = UserDefaults.standard.data(forKey: summaryKey(for: session)) else { return nil }
        return try? JSONDecoder().decode(ClaudeCodeSummariser.ConclusionSummary.self, from: data)
    }

    private static func saveSummarisedDigest(
        _ digest: String,
        summary: ClaudeCodeSummariser.ConclusionSummary,
        for session: String
    ) {
        UserDefaults.standard.set(digest, forKey: digestKey(for: session))
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: summaryKey(for: session))
        }
    }

    // MARK: Sending

    /// Sends the composer's contents to the session and reloads the pane.
    func send() async {
        let command = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !isSending else { return }
        guard let credential = store.loadCredential(for: config) else {
            errorMessage = "No stored credential for this connection."
            return
        }

        isSending = true
        pendingCommand = command
        draft = ""
        defer { isSending = false }

        do {
            let snapshot = try await tmux.sendCommand(
                command,
                to: sessionName,
                lines: scrollbackLines,
                config: config,
                credential: credential
            )
            let parsed = await TranscriptParser.parsed(snapshot)
            transcript = parsed
            errorMessage = nil
            summariseIfNewConclusion(parsed.claudeCode?.activity)
        } catch {
            errorMessage = friendly(error)
            // Give the command back rather than swallowing it.
            draft = command
        }
        pendingCommand = nil
    }

    /// Ctrl-C, for when the pane is sitting on something that won't return.
    func interrupt() async {
        guard let credential = store.loadCredential(for: config) else { return }
        do {
            try await tmux.sendKeys("C-c", to: sessionName, config: config, credential: credential)
            await refresh()
        } catch {
            errorMessage = friendly(error)
        }
    }

    private func friendly(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
