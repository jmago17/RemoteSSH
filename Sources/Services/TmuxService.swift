import Foundation

/// Builds tmux commands and parses their output into `TmuxSession` values.
///
/// Each method owns a full connect → work → disconnect cycle so the
/// non-Sendable `RemoteShell` never escapes a nonisolated async scope. Callers
/// (e.g. the `@MainActor` view model) only ever exchange Sendable values.
struct TmuxService {
    /// Fields, pipe-separated. `pane_title` stays last because it may itself
    /// contain a `|` — Claude Code puts the current task there — so the tail is
    /// rejoined rather than indexed.
    static let listFormat = "#S|#{session_attached}|#{session_created}|#{session_activity}|#{pane_current_command}|#{pane_height}|#{pane_title}"

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

            // Read once for every session. Records whose pane no longer runs
            // an agent are dropped below — a hook can't publish "I was killed".
            let states = AgentState.parse((try? await shell.run(Self.readAgentStateCommand)) ?? "")

            var sessions: [TmuxSession] = []
            for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count >= 4 else { continue }

                let name = String(parts[0])
                let attached = parts[1] == "1"
                let created = Date(timeIntervalSince1970: Double(parts[2]) ?? 0)
                let activity = Date(timeIntervalSince1970: Double(parts[3]) ?? 0)
                let command = parts.count > 4 ? String(parts[4]) : ""
                let height = parts.count > 5 ? Int(parts[5]) ?? 0 : 0
                // A title may legitimately contain "|", so keep the tail whole.
                let title = parts.count > 6 ? parts[6...].joined(separator: "|") : ""

                // An agent's last line is its own chrome — Claude Code's mode
                // bar ("auto mode on…"), Codex's status bar — and says nothing
                // about the session. Read enough of the pane to find the
                // spinner and summarise the real state instead.
                //
                // Codex is read from the frame alone here, without the `ps`
                // check `snapshot` does: one extra round trip per *session* is
                // a different price from one per open chat, and the textual
                // test is deliberately narrow. Worst case a node pane gets an
                // agent-shaped one-line preview and the chat screen, which does
                // run the `ps` check, corrects it on open.
                let isClaude = ClaudeCodeRecogniser.isClaudeCode(command: command)
                let mightBeCodex = CodexRecogniser.isGenericInterpreter(command: command)
                let deep = isClaude || mightBeCodex
                let pane = (try? await shell.run(
                    "\(Self.pathPrefix) tmux capture-pane -p -J -t \(Self.quote(name)) -S -\(deep ? 40 : 3) 2>/dev/null || true"
                )) ?? ""

                // Same screen-vs-scrollback split the chat view makes: state is
                // read from the visible screen only, or a question answered an
                // hour ago still reads as "waiting for your answer".
                let snapshot = PaneSnapshot(text: pane, currentCommand: command, paneTitle: title, paneHeight: height)
                let screen = snapshot.visibleScreen

                // The hooks are the better source when they have something
                // to say: a real signal from the process beats inference about
                // its output. Falls through to reading the screen when there
                // is no record, which covers agents started before the hooks
                // were installed and anything running on another machine.
                let hookState = states
                    .filter { $0.session == name && !$0.isStale(command: command) }
                    .max(by: { $0.updated < $1.updated })

                let preview: String
                if let hookState {
                    preview = hookState.status().summary
                } else if isClaude {
                    preview = ClaudeCodeRecogniser.status(text: screen, paneTitle: title).summary
                } else if mightBeCodex,
                          CodexRecogniser.isCodex(command: command, foregroundProcesses: "", text: screen) {
                    preview = CodexRecogniser.status(text: screen, paneTitle: title).summary
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

    /// Narrows a session's window so its lines fit the phone, and **only when
    /// nobody is looking at it on the Mac**.
    ///
    /// **Why this is needed at all.** A pane on a desktop terminal is typically
    /// 162 columns. Fitting 162 columns into an iPhone's ~374pt needs about
    /// 3.6pt of type — unreadable — so the transcript can only offer sideways
    /// scrolling. No amount of font fitting solves that: the width is simply
    /// impossible.
    ///
    /// The app already caused the fix by accident. Opening the terminal
    /// attaches a client, tmux resizes the window to what that client can
    /// show, and the transcript suddenly looks right — until the client goes
    /// away and `window-size latest` hands the window back to the Mac's
    /// dimensions. This does the same resize deliberately, without the
    /// round-trip through the terminal view.
    ///
    /// Guarded three ways:
    /// - `#{session_attached}` must be 0. If a terminal on the Mac has it
    ///   open, reflowing it under the user's hands is not the app's business.
    /// - Only ever narrows. A wider pane is never forced on anyone.
    /// - Reversible on its own: attaching from the Mac resizes it straight
    ///   back, because tmux is on `window-size latest`.
    ///
    /// - Returns: whether it actually resized, so the caller knows to re-read.
    @discardableResult
    func fitWindow(
        to columns: Int,
        session name: String,
        config: SSHConnectionConfig,
        credential: SSHCredential
    ) async throws -> Bool {
        guard columns >= 40 else { return false }
        return try await withShell(config: config, credential: credential) { shell in
            // One round trip: ask and act in the same shell, so the answer
            // can't go stale between the two.
            let script = """
            export \(Self.pathPrefix);             info=$(tmux display-message -p -t \(Self.quote(name)) '#{session_attached}|#{pane_width}' 2>/dev/null);             attached=${info%%|*}; width=${info##*|};             if [ "$attached" = "0" ] && [ "${width:-0}" -gt \(columns) ]; then               tmux resize-window -t \(Self.quote(name)) -x \(columns) 2>/dev/null && echo __RESIZED__;             fi
            """
            return (try await shell.run(script)).contains("__RESIZED__")
        }
    }

    /// Writes a small file on the Mac over SSH.
    ///
    /// Used for the APNs device token, which the Mac's push sender reads. The
    /// content is passed through base64 rather than interpolated into the
    /// command: a device token is hex and harmless, but a shell command built
    /// by string concatenation is a habit that eventually meets a value that
    /// isn't.
    func writeRemoteFile(
        _ contents: String,
        to path: String,
        config: SSHConnectionConfig,
        credential: SSHCredential
    ) async throws {
        let encoded = Data(contents.utf8).base64EncodedString()
        let expanded = path.hasPrefix("~/") ? "$HOME/" + path.dropFirst(2) : path
        try await withShell(config: config, credential: credential) { shell in
            // mkdir -p first: the directory won't exist before the agent hooks
            // have ever run.
            _ = try await shell.run(
                "mkdir -p \"$(dirname \"\(expanded)\")\" && printf %s \(Self.quote(encoded)) | base64 -d > \"\(expanded)\""
            )
        }
    }

    // MARK: Copy mode (terminal scrollback)

    /// Puts the pane in or out of tmux's copy mode — the only way to see
    /// anything above the last screen while attached.
    ///
    /// **Why this goes over a separate SSH command instead of through the
    /// attached PTY.** The keyboard route is `prefix` + `[`, and the prefix is
    /// whatever the user configured: C-b by default, C-a for a large minority,
    /// anything at all for the rest. Sending 0x02 and hoping is exactly the
    /// kind of guess this app tries not to make. `tmux copy-mode -t <pane>`
    /// asks the server directly and is prefix-independent.
    ///
    /// Paging, by contrast, *does* go through the PTY: PageUp/PageDown are
    /// bound to page-up/page-down in both the emacs and vi copy-mode tables,
    /// so they need no prefix, and routing them through the live channel keeps
    /// scrolling instant instead of one SSH connection per page.
    func setCopyMode(_ on: Bool, session name: String, config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            let command = on
                ? "tmux copy-mode -t \(Self.quote(name))"
                : "tmux send-keys -X -t \(Self.quote(name)) cancel"
            _ = try await shell.run("\(Self.pathPrefix) \(command) 2>/dev/null || true")
        }
    }

    /// Runs one copy-mode command (`history-top`, `history-bottom`, …) by name.
    /// Used for the jumps that *are* bound differently between the emacs and vi
    /// key tables, where a keystroke would be a guess but the command name is
    /// the same either way.
    func sendCopyModeCommand(_ command: String, session name: String, config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            _ = try await shell.run(
                "\(Self.pathPrefix) tmux send-keys -X -t \(Self.quote(name)) \(Self.quote(command)) 2>/dev/null || true"
            )
        }
    }

    /// `#{pane_in_mode}` — whether the pane is in copy mode right now.
    ///
    /// Worth asking rather than assuming: the user can leave copy mode from the
    /// keyboard (`q`, Escape) without the app hearing about it, which would
    /// otherwise leave the history bar on screen driving a pane that is back to
    /// taking input.
    func isInCopyMode(session name: String, config: SSHConnectionConfig, credential: SSHCredential) async throws -> Bool {
        try await withShell(config: config, credential: credential) { shell in
            let out = try await shell.run(
                "\(Self.pathPrefix) tmux display-message -p -t \(Self.quote(name)) '#{pane_in_mode}' 2>/dev/null || true"
            )
            return out.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
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
    /// Everything the lifecycle hooks have published, as JSONL — one record
    /// per pane. One command for every session, rather than one per session:
    /// the whole point of this path is that it costs almost nothing.
    ///
    /// `|| true` because the glob matches nothing when no agent has ever run,
    /// and "no state" is an answer, not a failure.
    static let readAgentStateCommand =
        #"cat "$HOME"/.remotessh/state/*.json 2>/dev/null || true"#

    static func captureCommand(session name: String, lines: Int) -> String {
        "\(pathPrefix) tmux capture-pane -p -J -t \(quote(name)) -S -\(lines) 2>/dev/null || true"
    }

    private static func snapshot(_ shell: RemoteShell, session name: String, lines: Int) async throws -> PaneSnapshot {
        let text = try await shell.run(captureCommand(session: name, lines: lines))
        // One round trip for the pane facts. `pane_title` is last because
        // Claude Code puts the current task there and it may contain spaces —
        // and `|` — so the tail is rejoined rather than indexed.
        let info = (try? await shell.run(
            "\(pathPrefix) tmux display-message -p -t \(quote(name)) '#{alternate_on}|#{pane_current_command}|#{pane_tty}|#{pane_height}|#{pane_width}|#{pane_id}|#{pane_title}' 2>/dev/null || true"
        )) ?? ""

        let parts = info.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false)
        let command = parts.count > 1 ? String(parts[1]) : ""
        let tty = parts.count > 2 ? String(parts[2]) : ""
        let height = parts.count > 3 ? Int(parts[3]) ?? 0 : 0
        let paneWidth = parts.count > 4 ? Int(parts[4]) ?? 0 : 0
        let pane = parts.count > 5 ? String(parts[5]) : ""

        // A second round trip, but only for panes whose process name explains
        // nothing. Codex reports as a bare `node`, so without this it is
        // indistinguishable from any other node process; `claude.exe`, `zsh`
        // and `vim` need no such help and don't pay for it.
        //
        // Asked by tty, not by pid: `#{pane_pid}` is the shell tmux started,
        // and an agent the user launched by typing its name is a *child* of
        // that shell — `ps -p #{pane_pid}` answers `-zsh`. Every process in the
        // pane shares the tty, so this finds the child. `stat` comes along so
        // the recogniser can tell the foreground group (`S+`) from leftovers
        // that merely inherited the terminal.
        var foreground = ""
        if CodexRecogniser.isGenericInterpreter(command: command), !tty.isEmpty {
            let device = tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
            foreground = ((try? await shell.run(
                "ps -t \(quote(device)) -o stat=,args= 2>/dev/null || true"
            )) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Same records, filtered to this pane. Cheap enough to fetch on every
        // chat refresh: it's one `cat` on a connection that is already open.
        let states = AgentState.parse((try? await shell.run(readAgentStateCommand)) ?? "")
        let paneState = states
            .filter { $0.pane == pane || $0.session == name }
            .max(by: { $0.updated < $1.updated })

        return PaneSnapshot(
            text: text,
            alternateScreen: parts.first.map { $0 == "1" } ?? false,
            currentCommand: command,
            paneTitle: parts.count > 6 ? parts[6...].joined(separator: "|") : "",
            paneHeight: height,
            paneWidth: paneWidth,
            foregroundProcesses: foreground,
            agentState: paneState
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
