import Foundation
import Observation

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
            transcript = await TranscriptParser.parsed(snapshot)
            errorMessage = nil
            pendingCommand = nil
        } catch {
            errorMessage = friendly(error)
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
            transcript = await TranscriptParser.parsed(snapshot)
            errorMessage = nil
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
