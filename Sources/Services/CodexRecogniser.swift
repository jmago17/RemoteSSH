import Foundation

/// Reads a Codex pane the way `ClaudeCodeRecogniser` reads a Claude Code one:
/// enough to answer *is it working, waiting for me, or idle*, and nothing more.
/// The frame itself is still shown verbatim — Codex hard-wraps its own output
/// to the pane width, so reflowing it into bubbles would corrupt paths exactly
/// as it would for Claude Code.
///
/// **Codex is harder to spot than Claude Code, and the reason is the process
/// name.** tmux reports Claude Code as `claude.exe`, which is unmistakable.
/// Codex reports as **`node`** — indistinguishable from a dev server, a build
/// watcher, or any other of the dozen node processes a developer has running.
/// Guessing from the frame alone would mean calling any node pane that happens
/// to print a `›` a Codex session.
///
/// So detection is done from the process arguments instead:
/// `ps -o args= -p #{pane_pid}` returns `node /opt/homebrew/bin/codex`, which
/// is a fact rather than a guess. The textual test below is only a fallback for
/// when those arguments couldn't be read, and it is deliberately narrow.
///
/// Everything here was checked against a real Codex 0.147.0 pane, and the
/// differences from Claude Code are not cosmetic:
///
/// | | Claude Code | Codex |
/// |---|---|---|
/// | `pane_current_command` | `claude.exe` | `node` |
/// | `alternate_on` | 1 | **0** — Codex never leaves the normal screen |
/// | `pane_title` | the task | the **cwd**, braille-spinner-prefixed while busy |
/// | spinner | `✽ Verb… (7m 3s · ↓22k tokens)` | `• Verb (2s • esc to interrupt)` |
/// | composer | `❯` | `›` |
enum CodexRecogniser {

    /// Process names that could be hosting *anything*, Codex included. Only
    /// these are worth the extra `ps` round trip — `claude.exe`, `zsh` or `vim`
    /// tell us what they are on their own.
    static let genericInterpreters: Set<String> = ["node", "bun", "deno", "python", "python3"]

    static func isGenericInterpreter(command: String) -> Bool {
        genericInterpreters.contains(stem(of: command))
    }

    /// True when this pane is running Codex.
    ///
    /// - Parameters:
    ///   - command: tmux `#{pane_current_command}` — `node` for Codex.
    ///   - processArgs: `ps -o args=` for `#{pane_pid}`, when it could be read.
    ///     This is the reliable signal; everything else is a fallback.
    ///   - text: the captured frame, used only when `processArgs` is empty.
    static func isCodex(command: String, processArgs: String, text: String) -> Bool {
        // Only a generic interpreter can be Codex in disguise. This guard is
        // what stops the textual fallback from ever firing on, say, a shell
        // that happens to be printing Codex's own output in a log.
        guard isGenericInterpreter(command: command) else { return false }

        if !processArgs.isEmpty {
            return mentionsCodexBinary(processArgs)
        }
        return looksLikeCodexFrame(text)
    }

    /// `node /opt/homebrew/bin/codex` → true; `node codex-server.js` → false.
    /// Matched as a whole path component so a project directory called
    /// `codex-web` can't pass for the binary.
    private static func mentionsCodexBinary(_ args: String) -> Bool {
        args.range(of: #"(^|[/\s])codex(\s|$)"#, options: .regularExpression) != nil
    }

    /// Last-resort recognition from the frame, for when `ps` wasn't available.
    ///
    /// Requires **two** independent marks, because either alone is common
    /// enough in ordinary output to be a false positive: the composer line that
    /// starts with `›`, and Codex's own status bar — `<model> · <absolute
    /// path>` — as the last non-empty line. The startup banner is accepted on
    /// its own since nothing else prints it, but it scrolls away within a
    /// session, so it can't be the only test.
    private static func looksLikeCodexFrame(_ text: String) -> Bool {
        let lines = normalised(text)
        guard !lines.isEmpty else { return false }

        if lines.contains(where: { $0.contains("OpenAI Codex (") }) { return true }

        let hasComposer = lines.contains { $0.hasPrefix("›") }
        let hasStatusBar = lines.last(where: { !$0.isEmpty })
            .map { $0.range(of: #"\s·\s/"#, options: .regularExpression) != nil } ?? false
        return hasComposer && hasStatusBar
    }

    // MARK: - Status

    /// Reads the pane frame. Pure: text in, values out.
    ///
    /// - Parameters:
    ///   - text: the `capture-pane` frame.
    ///   - paneTitle: tmux `#{pane_title}`. Codex sets it to the working
    ///     directory, prefixed with an animating braille spinner while busy.
    static func status(text: String, paneTitle: String = "") -> AgentStatus {
        let lines = normalised(text)

        // The braille prefix in the title is the cheapest and most reliable
        // "it's busy" signal there is: it comes straight from tmux, needs no
        // frame parsing, and is present even when the spinner line itself has
        // scrolled past the bottom of what we captured.
        let titleSaysBusy = hasBrailleSpinner(paneTitle)

        if let spinner = lines.last(where: isSpinnerLine) {
            return AgentStatus(
                agent: .codex,
                activity: .working(verb: verb(in: spinner)),
                elapsed: capture(spinner, pattern: #"\((\d+m \d+s|\d+s)\b"#)
            )
        }

        if titleSaysBusy {
            return AgentStatus(agent: .codex, activity: .working(verb: "Working"))
        }

        if lines.contains(where: isApprovalPrompt) {
            return AgentStatus(agent: .codex, activity: .awaitingApproval)
        }

        return AgentStatus(agent: .codex, activity: .idle)
    }

    // MARK: - Line tests

    /// `• Starting MCP servers (4/5): codex_apps (2s • esc to interrupt)`
    ///
    /// Anchored on `esc to interrupt`, which Codex prints only while something
    /// is actually running. Note it does *not* require the `…` that Claude
    /// Code's spinner carries — Codex doesn't print one, and requiring it was
    /// the reason the Claude recogniser can't be reused here.
    private static func isSpinnerLine(_ line: String) -> Bool {
        line.contains("esc to interrupt")
    }

    /// Codex asks for a decision with a numbered list, marking the current
    /// choice with `›`:
    ///
    /// ```
    /// › 1. Review hooks
    ///   2. Trust all and continue
    ///   Press enter to confirm or esc to go back
    /// ```
    ///
    /// The `›` alone means nothing — it's also the composer's own prefix
    /// (`› Improve documentation in @filename` is what an *idle* pane shows),
    /// so the digit is doing the work.
    private static func isApprovalPrompt(_ line: String) -> Bool {
        if line.hasPrefix("Press enter to confirm") { return true }
        return line.range(of: #"^›\s*\d+\.\s+\S"#, options: .regularExpression) != nil
    }

    /// Pulls the verb out of a spinner line: everything between the leading
    /// bullet and the parenthesised timer. Capped, because Codex sometimes puts
    /// a whole progress report in there (`Starting MCP servers (4/5):
    /// codex_apps`) and the banner has one line to work with.
    private static func verb(in line: String) -> String {
        var body = line
        if body.hasPrefix("•") { body = String(body.dropFirst()) }
        // Cut at the last `(`, which opens the timer.
        if let open = body.range(of: "(", options: .backwards) {
            body = String(body[body.startIndex..<open.lowerBound])
        }
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Working" }
        guard trimmed.count > 40 else { return trimmed }
        // Trim again after the cut: chopping mid-sentence usually lands on a
        // space, and " …" reads as a typo rather than a truncation.
        return String(trimmed.prefix(39)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Codex prefixes the pane title with an animating braille frame
    /// (`⠙ myproject`) while it works, and drops it when idle.
    private static func hasBrailleSpinner(_ title: String) -> Bool {
        guard let first = title.trimmingCharacters(in: .whitespaces).unicodeScalars.first else { return false }
        return (0x2800...0x28FF).contains(Int(first.value))
    }

    // MARK: - Helpers

    private static func stem(of command: String) -> String {
        let name = command.hasPrefix("-") ? String(command.dropFirst()) : command
        return (name.split(separator: ".").first.map(String.init) ?? name).lowercased()
    }

    private static func normalised(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func capture(_ s: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s)
        else { return nil }
        let value = String(s[r]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
