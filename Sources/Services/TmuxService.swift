import Foundation

/// Builds tmux commands and parses their output into `TmuxSession` values.
///
/// Each method owns a full connect → work → disconnect cycle so the
/// non-Sendable `RemoteShell` never escapes a nonisolated async scope. Callers
/// (e.g. the `@MainActor` view model) only ever exchange Sendable values.
struct TmuxService {
    /// Fields, pipe-separated: name | attached | created | activity
    static let listFormat = "#S|#{session_attached}|#{session_created}|#{session_activity}|#{pane_current_command}|#{pane_title}"

    /// Non-interactive SSH exec channels get a minimal PATH
    /// (`/usr/bin:/bin:/usr/sbin:/sbin`), which omits Homebrew. Prefix every
    /// command so `tmux` resolves on both Apple-Silicon and Intel installs.
    static let pathPrefix = #"PATH="$PATH:/opt/homebrew/bin:/usr/local/bin""#

    /// Fetches every session plus a short pane preview for each, over a single
    /// SSH connection.
    func fetchSessions(config: SSHConnectionConfig, credential: SSHCredential) async throws -> [TmuxSession] {
        try await withShell(config: config, credential: credential) { shell in
            // `|| true` keeps the exit code zero when tmux has no server
            // running, so we surface "no sessions" rather than an error.
            let raw = try await shell.run(
                "\(Self.pathPrefix) tmux list-sessions -F '\(Self.listFormat)' 2>/dev/null || true"
            )

            var sessions: [TmuxSession] = []
            for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count >= 4 else { continue }

                let name = String(parts[0])
                let attached = parts[1] == "1"
                let created = Date(timeIntervalSince1970: Double(parts[2]) ?? 0)
                let activity = Date(timeIntervalSince1970: Double(parts[3]) ?? 0)
                let command = parts.count > 4 ? String(parts[4]) : ""
                // A title may legitimately contain "|", so keep the tail whole.
                let title = parts.count > 5 ? parts[5...].joined(separator: "|") : ""

                // Claude Code's last line is its mode bar ("auto mode on…"),
                // which says nothing about the session. Read enough of the pane
                // to find the spinner and summarise the real state instead.
                let isClaude = ClaudeCodeRecogniser.isClaudeCode(command: command)
                let pane = (try? await shell.run(
                    "\(Self.pathPrefix) tmux capture-pane -p -J -t \(Self.quote(name)) -S -\(isClaude ? 40 : 3) 2>/dev/null || true"
                )) ?? ""

                let preview: String
                if isClaude {
                    preview = ClaudeCodeRecogniser.status(text: pane, paneTitle: title).summary
                } else {
                    preview = Self.lastNonEmptyLine(pane)
                }

                sessions.append(
                    TmuxSession(
                        name: name,
                        isAttached: attached,
                        created: created,
                        lastActivity: activity,
                        preview: preview,
                        contentHash: pane.hashValue
                    )
                )
            }
            // Most recently active first — like a chat list.
            return sessions.sorted { $0.lastActivity > $1.lastActivity }
        }
    }

    /// Full scrollback for the read-only "thread" view (Phase 1).
    func captureScrollback(
        session name: String,
        lines: Int = 2000,
        config: SSHConnectionConfig,
        credential: SSHCredential
    ) async throws -> String {
        try await withShell(config: config, credential: credential) { shell in
            try await shell.run(Self.captureCommand(session: name, lines: lines))
        }
    }

    /// Scrollback *plus* the two facts about the pane that stop the transcript
    /// parser from having to guess: whether a full-screen program owns the
    /// screen, and which process is in the foreground.
    ///
    /// Both run over one connection — asking tmux costs a few bytes on a channel
    /// that's already open, and it turns "is this vim?" from a heuristic into a
    /// fact.
    func capturePane(
        session name: String,
        lines: Int = 2000,
        config: SSHConnectionConfig,
        credential: SSHCredential
    ) async throws -> PaneSnapshot {
        try await withShell(config: config, credential: credential) { shell in
            try await Self.snapshot(shell, session: name, lines: lines)
        }
    }

    /// Types `command` into a session and presses Enter, then waits for the pane
    /// to settle and returns what it looks like afterwards.
    ///
    /// There is no completion callback for `send-keys`, so the alternative to
    /// waiting is a blind `sleep` — which truncates slow commands and wastes
    /// time on fast ones. Instead this polls a cheap change signal
    /// (`#{history_size} #{cursor_y}`, a few bytes) and captures once the signal
    /// holds still, all on the same connection.
    func sendCommand(
        _ command: String,
        to name: String,
        lines: Int = 2000,
        config: SSHConnectionConfig,
        credential: SSHCredential
    ) async throws -> PaneSnapshot {
        try await withShell(config: config, credential: credential) { shell in
            // `-l` is load-bearing, not decoration: without it tmux resolves the
            // argument as a *key name* first, so a command that happens to read
            // `Enter`, `Space` or `C-c` would be delivered as that keystroke
            // instead of as text. Send the text literally, then Enter as its own
            // key. `quote` handles the outer shell layer.
            _ = try await shell.run(
                "\(Self.pathPrefix) tmux send-keys -t \(Self.quote(name)) -l \(Self.quote(command)) 2>/dev/null || true"
            )
            _ = try await shell.run(
                "\(Self.pathPrefix) tmux send-keys -t \(Self.quote(name)) Enter 2>/dev/null || true"
            )

            var previousSignal = ""
            var stableRounds = 0
            // ~6s ceiling: past that we show what there is rather than hang. A
            // long build keeps printing and simply gets picked up by the next
            // refresh.
            for round in 0..<20 {
                try await Task.sleep(for: .milliseconds(300))
                let signal = try await shell.run(
                    "\(Self.pathPrefix) tmux display-message -p -t \(Self.quote(name)) '#{history_size} #{cursor_y}' 2>/dev/null || true"
                )
                if signal == previousSignal {
                    stableRounds += 1
                    // Two quiet rounds after something moved. The first round is
                    // never enough to conclude anything.
                    if stableRounds >= 2 && round > 0 { break }
                } else {
                    stableRounds = 0
                    previousSignal = signal
                }
            }

            return try await Self.snapshot(shell, session: name, lines: lines)
        }
    }

    /// Sends a bare control key (Ctrl-C and friends) without waiting — used to
    /// get a wedged pane back to a prompt from the chat view.
    func sendKeys(_ keys: String, to name: String, config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            _ = try await shell.run(
                "\(Self.pathPrefix) tmux send-keys -t \(Self.quote(name)) \(Self.quote(keys)) 2>/dev/null || true"
            )
        }
    }

    /// `-J` joins lines that tmux wrapped at the pane width. Without it a long
    /// command or a long output line arrives pre-split, and the continuations
    /// look like new lines to the parser — which is exactly how an output ends
    /// up attributed to the wrong command.
    static func captureCommand(session name: String, lines: Int) -> String {
        "\(pathPrefix) tmux capture-pane -p -J -t \(quote(name)) -S -\(lines) 2>/dev/null || true"
    }

    private static func snapshot(_ shell: RemoteShell, session name: String, lines: Int) async throws -> PaneSnapshot {
        let text = try await shell.run(captureCommand(session: name, lines: lines))
        // One round trip for all three facts. `pane_title` is last because
        // Claude Code puts the current task there and it may contain spaces.
        let info = (try? await shell.run(
            "\(pathPrefix) tmux display-message -p -t \(quote(name)) '#{alternate_on}|#{pane_current_command}|#{pane_title}' 2>/dev/null || true"
        )) ?? ""

        let parts = info.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false)
        return PaneSnapshot(
            text: text,
            alternateScreen: parts.first.map { $0 == "1" } ?? false,
            currentCommand: parts.count > 1 ? String(parts[1]) : "",
            paneTitle: parts.count > 2 ? parts[2...].joined(separator: "|") : ""
        )
    }

    func killSession(_ name: String, config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            _ = try await shell.run("\(Self.pathPrefix) tmux kill-session -t \(Self.quote(name)) 2>/dev/null || true")
        }
    }

    func renameSession(_ name: String, to newName: String, config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            _ = try await shell.run(
                "\(Self.pathPrefix) tmux rename-session -t \(Self.quote(name)) \(Self.quote(newName)) 2>/dev/null || true"
            )
        }
    }

    /// Creates a new detached session. `tmux new-session -d` starts a server if
    /// none is running, so this works from a cold machine too.
    func createSession(_ name: String, config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            _ = try await shell.run("\(Self.pathPrefix) tmux new-session -d -s \(Self.quote(name)) 2>/dev/null || true")
        }
    }

    /// Restores previously-saved tmux sessions via the tmux-resurrect plugin
    /// (e.g. after a Mac reboot). Returns `true` if the restore script ran,
    /// `false` if tmux-resurrect isn't installed.
    func restoreSessions(config: SSHConnectionConfig, credential: SSHCredential) async throws -> Bool {
        try await withShell(config: config, credential: credential) { shell in
            // Look in the common tmux-resurrect install locations (TPM default,
            // XDG config, and XDG data), run restore.sh if present.
            let script = """
            export \(Self.pathPrefix); \
            for d in "$HOME/.tmux/plugins/tmux-resurrect" "$HOME/.config/tmux/plugins/tmux-resurrect" "$HOME/.local/share/tmux/plugins/tmux-resurrect"; do \
              if [ -x "$d/scripts/restore.sh" ]; then "$d/scripts/restore.sh" >/dev/null 2>&1; echo __RESTORED__; exit 0; fi; \
            done; \
            echo __NORESURRECT__
            """
            let out = try await shell.run(script)
            return out.contains("__RESTORED__")
        }
    }

    /// Wakes the Mac's display (only works if the Mac already answers SSH).
    /// `caffeinate` lives in /usr/bin, so the minimal SSH PATH is fine.
    func wakeDisplay(config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            _ = try await shell.run("caffeinate -u -t 1 >/dev/null 2>&1 || true")
        }
    }

    // MARK: Connection lifecycle

    /// Runs `body` against a connected shell, guaranteeing disconnect. The
    /// `RemoteShell` is created and destroyed entirely within this nonisolated
    /// async scope, so its non-Sendable `SSHClient` never crosses a boundary.
    private func withShell<T: Sendable>(
        config: SSHConnectionConfig,
        credential: SSHCredential,
        _ body: (RemoteShell) async throws -> T
    ) async throws -> T {
        let shell = RemoteShell(config: config, credential: credential)
        do {
            try await shell.connect()
            let result = try await body(shell)
            await shell.disconnect()
            return result
        } catch {
            await shell.disconnect()
            throw error
        }
    }

    // MARK: Parsing helpers

    /// POSIX single-quote escaping so arbitrary session names are shell-safe.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func lastNonEmptyLine(_ text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
