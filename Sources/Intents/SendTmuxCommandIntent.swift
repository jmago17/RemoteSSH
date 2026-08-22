import AppIntents

/// Sends a command to a tmux session on the configured Mac — the Shortcuts
/// equivalent of typing into the app's chat composer.
///
/// Runs `.background`: firing this from an Automation (e.g. "when I arrive at
/// the office") should not have to yank the app to the foreground. It reuses
/// exactly the path the in-app composer uses (`TmuxService.sendCommand`), so
/// there is no second, less-tested way to talk to tmux.
struct SendTmuxCommandIntent: AppIntent {
    static var title: LocalizedStringResource { "Send tmux Command" }
    /// **Do not put the word "Mac" back in any of the strings below.** App
    /// Store validation rejects the build outright:
    ///
    ///     ITMS-90626: Invalid Siri Support - App Intent description '…'
    ///     cannot contain 'mac'
    ///
    /// It's matched as a substring, so "machine" and "macOS" are out too. The
    /// rule applies to everything extracted into the App Intents metadata —
    /// this description *and* the parameter descriptions below — not just the
    /// one string the rejection happened to name. Comments are fine; only the
    /// literals ship.
    static var description: IntentDescription {
        IntentDescription(
            "Sends a command to a tmux session over SSH, as if you'd typed it into RemoteSSH's chat.",
            categoryName: "tmux"
        )
    }

    static var openAppWhenRun: Bool { false }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Session", description: "The tmux session to send to.")
    var session: TmuxSessionEntity

    @Parameter(title: "Command", description: "The command to run, exactly as you'd type it.")
    var command: String

    @Parameter(title: "Host", description: "Which host to send to. Defaults to the active one.")
    var host: SSHHostEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$command) to \(\.$session)") {
            \.$host
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SettingsStore()
        let config = resolvedConfig(host: host, store: store)

        guard config.isComplete else {
            throw TmuxIntentError.hostNotConfigured
        }
        guard let credential = store.loadCredential(for: config) else {
            throw TmuxIntentError.noStoredCredential(hostName: config.name)
        }

        do {
            let snapshot = try await TmuxService().sendCommand(
                command,
                to: session.id,
                config: config,
                credential: credential
            )
            // A short confirmation, not the pane dump: Shortcuts renders
            // dialog text inline (widgets, Siri speech, notification banners)
            // and a multi-line tmux frame is the wrong shape for any of them.
            // The app is one tap away — via the ntfy deep link or opening it —
            // for the real transcript.
            let hint = TranscriptParser.parse(snapshot).turns.last.map(Self.oneLine)
            let confirmation = hint.map { "Sent to \(session.id). Last line: \($0)" }
                ?? "Sent to \(session.id)."
            return .result(dialog: IntentDialog(stringLiteral: confirmation))
        } catch {
            throw TmuxIntentError.sendFailed(sessionName: session.id, underlying: error)
        }
    }

    /// The confirmation dialog needs one line, not a turn's full (possibly
    /// multi-line) text — Shortcuts renders this inline in a widget, Siri
    /// speech, or a notification banner.
    private static func oneLine(_ turn: TranscriptTurn) -> String {
        let line = turn.text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last.map(String.init) ?? turn.text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
    }

    /// Falls back to the app's active host when no host parameter was
    /// resolved (the common case: one Mac, nothing to disambiguate).
    private func resolvedConfig(host: SSHHostEntity?, store: SettingsStore) -> SSHConnectionConfig {
        guard let host, let uuid = UUID(uuidString: host.id) else {
            return store.activeConfig()
        }
        return store.loadHosts().first { $0.id == uuid } ?? store.activeConfig()
    }
}

enum TmuxIntentError: LocalizedError {
    case hostNotConfigured
    case noStoredCredential(hostName: String)
    case sendFailed(sessionName: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .hostNotConfigured:
            return "No host is configured in RemoteSSH yet. Open the app and add one first."
        case .noStoredCredential(let hostName):
            return "No stored credential for \(hostName). Open RemoteSSH and reconnect once."
        case .sendFailed(let sessionName, let underlying):
            return "Couldn't send to \(sessionName): \(underlying.localizedDescription)"
        }
    }
}
