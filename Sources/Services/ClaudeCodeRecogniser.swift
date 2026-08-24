import Foundation

/// Which coding agent owns a pane.
///
/// Kept separate from the recogniser that produced it because the *state* — is
/// it working, is it waiting for me, is it idle — is the same question for both
/// agents and the UI asks it the same way. Only the reading of the frame
/// differs, and that lives in one recogniser per agent.
enum AgentKind: String, Hashable, Sendable {
    case claudeCode
    case codex

    /// What the banner calls it. Shown to the user, so it's the product name.
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

/// What an agent pane is doing right now.
///
/// **Why this exists as a separate type.** `TranscriptParser` refuses to slice a
/// pane while a curses app owns the screen, and that rule is right: `htop` and
/// `vim` redraw a *frame*, and cutting a frame into turns invents history that
/// never happened. Claude Code trips the same wire — it runs on the alternate
/// screen — so the chat view used to fall back to a raw dump and tell the user
/// to open the terminal.
///
/// That is the wrong answer for the app's single most common session. But the
/// fix is *not* to reflow Claude Code's body into chat bubbles: it hard-wraps
/// its own text to the pane width before tmux ever sees it, so a path can
/// arrive split as `Pl` + `atforms`. Un-wrapping that means guessing whether a
/// line break is real, and a wrong guess corrupts a command someone may copy.
///
/// So this type deliberately reads only the parts that are *stable and
/// unambiguous* — the status line, the mode line, the pane title — and answers
/// one question: **is it working, waiting for me, or idle?** The frame itself is
/// still shown verbatim underneath. We summarise; we never re-render.
struct AgentStatus: Hashable, Sendable {

    enum Activity: Hashable, Sendable {
        /// A spinner line is present: Claude is doing something.
        case working(verb: String)
        /// Claude asked something and the pane is showing choices.
        case awaitingApproval
        /// No spinner, no question: the composer is sitting there.
        case idle
        /// The turn ended on an API error. Only ever reported by the hooks —
        /// the screen can't tell this apart from an ordinary idle pane, which
        /// is precisely why waiting on a notification that never came used to
        /// be the failure mode.
        case failed
    }

    /// Where this reading came from. Kept so a wrong banner can be traced to
    /// the right place while both paths coexist.
    enum Source: Hashable, Sendable {
        /// The agent's own lifecycle hooks, via a state file on the Mac.
        case hook
        /// Inferred by reading the terminal. The fallback.
        case screen
    }

    /// Which agent this describes. Defaults to Claude Code so the existing
    /// call sites keep reading the way they did.
    var agent: AgentKind = .claudeCode
    var activity: Activity
    var source: Source = .screen
    /// The current task, when the agent publishes one in the pane title.
    /// Claude Code does; Codex puts its working directory there instead, which
    /// is not a task, so its recogniser leaves this `nil` rather than dress a
    /// path up as one.
    var task: String?
    /// Elapsed time as Claude renders it, e.g. `7m 3s`.
    var elapsed: String?
    /// Token counter as rendered, e.g. `22.4k`.
    var tokens: String?
    /// The trailing detail some spinners carry, e.g. `thinking`.
    var detail: String?
    /// The turn's closing text, when it came from a hook.
    ///
    /// Only ever set on `.hook` readings, and that's the point: the screen path
    /// has to reconstruct this by scraping the pane and undoing Claude Code's
    /// own hard-wrapping, while the hook payload hands it over intact.
    var lastMessage: String?

    /// One line for a session row, built from whatever was available.
    var summary: String {
        switch activity {
        case .awaitingApproval:
            return "Waiting for your answer"
        case .failed:
            return "Stopped on an API error"
        case .idle:
            return task ?? agent.displayName
        case .working(let verb):
            var parts = [verb]
            if let elapsed { parts.append(elapsed) }
            if let tokens { parts.append("↓\(tokens)") }
            return parts.joined(separator: " · ")
        }
    }

    var needsAttention: Bool { activity == .awaitingApproval }
}

enum ClaudeCodeRecogniser {

    /// Process names tmux reports for Claude Code. It appears as `claude.exe`
    /// on this machine — matching the exact string `claude` would miss it.
    static func isClaudeCode(command: String) -> Bool {
        let name = command.hasPrefix("-") ? String(command.dropFirst()) : command
        let stem = name.split(separator: ".").first.map(String.init) ?? name
        return stem.lowercased() == "claude"
    }

    /// Reads the pane frame. Pure: text in, values out.
    ///
    /// - Parameters:
    ///   - text: the `capture-pane` frame.
    ///   - paneTitle: tmux `#{pane_title}`; Claude Code sets it to the task.
    static func status(text: String, paneTitle: String = "") -> AgentStatus {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        let task = cleanedTitle(paneTitle)

        // A spinner line is the strongest signal that work is in flight. The
        // leading glyph animates (✽ · ✻ ✢ …), so we anchor on the stable parts
        // instead: an ellipsis, then a parenthesised elapsed time.
        if let spinner = lines.last(where: isSpinnerLine) {
            return AgentStatus(
                activity: .working(verb: verb(in: spinner)),
                task: task,
                elapsed: capture(spinner, pattern: #"\((\d+m \d+s|\d+s)"#),
                tokens: capture(spinner, pattern: #"↓\s*([\d.]+k?)\s*tokens"#),
                detail: capture(spinner, pattern: #"·\s*([a-z ]+)\)"#)
            )
        }

        if lines.contains(where: isApprovalPrompt) {
            return AgentStatus(activity: .awaitingApproval, task: task)
        }

        return AgentStatus(activity: .idle, task: task)
    }

    // MARK: - Line tests

    /// `✽ Beaming… (7m 3s · ↓ 22.4k tokens · thinking)`
    ///
    /// Requires the ellipsis *and* a parenthesised duration, so ordinary prose
    /// ending in "…" can't masquerade as a spinner.
    private static func isSpinnerLine(_ line: String) -> Bool {
        guard line.contains("…") else { return false }
        return matches(line, pattern: #"\(\s*(\d+m \d+s|\d+s)\b"#)
    }

    /// Claude Code renders a numbered choice list when it wants a decision.
    /// `esc to interrupt` only appears while it is *running*, so its absence
    /// plus a choice list is a solid "it's your turn".
    private static func isApprovalPrompt(_ line: String) -> Bool {
        if line.contains("Do you want") || line.contains("Would you like") { return true }
        // `❯ 1. Yes` / `1. Yes, and don't ask again`
        return matches(line, pattern: #"^[❯>]?\s*\d+\.\s+(Yes|No)\b"#)
    }

    /// `✽ Beaming… (…)` → `Beaming`. Falls back to a neutral word so the UI
    /// never shows an empty state.
    private static func verb(in line: String) -> String {
        guard let raw = capture(line, pattern: #"([A-Za-z][A-Za-z-]*)…"#) else { return "Working" }
        return raw
    }

    /// Claude Code prefixes the title with a spinner/marker character while it
    /// works (`_ Fix NewsRaider…`). Strip leading punctuation and drop titles
    /// that are really just a hostname.
    private static func cleanedTitle(_ title: String) -> String? {
        var t = title.trimmingCharacters(in: .whitespaces)
        while let f = t.unicodeScalars.first,
              !CharacterSet.alphanumerics.contains(f) {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard t.count > 2 else { return nil }
        // Default tmux titles are the host, e.g. `MacBook-Air-de-Josu.local`.
        if t.hasSuffix(".local") || !t.contains(" ") { return nil }
        return t
    }

    // MARK: - Regex helpers

    private static func matches(_ s: String, pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
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

    // MARK: - Conclusion extraction

    /// Pulls out whatever Claude Code said right before it went idle — the
    /// text most likely to be "here's what I found/did", which is what
    /// `ClaudeCodeSummariser` reads.
    ///
    /// Heuristic like the rest of this file, and cheap on purpose: take
    /// everything from the *last* `⏺` marker (a new turn) down to the
    /// mode-bar / composer separator at the bottom, and drop the tool-call
    /// noise lines (`Running N shell command…`, `⎿  ...`) that are process,
    /// not conclusion. If no `⏺` is found, falls back to the last non-empty,
    /// non-chrome lines — better than nothing, worse than a real marker.
    static func lastConclusion(text: String, maxLines: Int = 40) -> String? {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let markerIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("⏺") }) else {
            return fallbackTail(lines, maxLines: maxLines)
        }

        let kept = dropProcessNoise(Array(lines[markerIndex...]))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let joined = kept.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// Drops tool-call chrome from a block of lines: `Running N shell
    /// command…`, its `⎿` result line, *and* that result's wrapped
    /// continuations. A continuation doesn't carry its own `⎿` marker — it's
    /// just more-indented text — so this tracks indentation rather than
    /// testing each line alone. Getting this wrong would staple a fragment
    /// like `atforms/iPhoneOS.platform/...` (the tail of a path Claude Code
    /// itself wrapped as `Pl` + `atforms`) onto the conclusion as if it were
    /// prose.
    private static func dropProcessNoise(_ lines: [String]) -> [String] {
        var kept: [String] = []
        var skippingBlockIndent: Int? = nil

        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let indent = raw.prefix(while: { $0 == " " }).count

            if let blockIndent = skippingBlockIndent {
                if trimmed.isEmpty { skippingBlockIndent = nil; continue }
                if indent >= blockIndent { continue } // still inside the quoted block
                skippingBlockIndent = nil // dedented back out — fall through and test normally
            }

            if trimmed.isEmpty { kept.append(raw); continue }
            if matches(trimmed, pattern: #"^Running \d+ shell command"#) { continue }
            if trimmed.hasPrefix("⎿") {
                skippingBlockIndent = indent
                continue
            }
            if trimmed.hasPrefix("─") || trimmed.hasPrefix("❯") { continue }
            if trimmed.contains("auto mode on") || trimmed.contains("esc to interrupt") { continue }
            if trimmed.hasPrefix("Tip:") { continue }
            kept.append(raw)
        }
        return kept
    }

    private static func fallbackTail(_ lines: [String], maxLines: Int) -> String? {
        let kept = dropProcessNoise(lines)
            .suffix(maxLines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = kept.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}
