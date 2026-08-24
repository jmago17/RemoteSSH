import Foundation

/// A state record written by the agent's own lifecycle hooks on the Mac
/// (`~/.claude/hooks/remotessh-notify.sh` → `~/.remotessh/state/<pane>.json`).
///
/// **Why this exists.** Everything the app knew about an agent used to come
/// from reading its terminal output: find a spinner, infer "working"; lose the
/// spinner, infer "idle". That works until the agent changes how it draws
/// itself — and Claude Code rotates its spinner glyph and verb constantly, so
/// the parser can only anchor on the shape of a parenthesised timer. It is
/// inference about a picture, not a signal from the process.
///
/// The hooks publish the real thing: Claude Code fires `UserPromptSubmit` when
/// a turn starts and `Stop` when it ends, and says so in JSON. Same events,
/// same file, for Codex.
///
/// The transport is deliberately boring: a file on the Mac, read over the SSH
/// connection the app already opens. No daemon, no server, no cloud relay,
/// nothing new to authenticate — the channel is already authenticated and the
/// Mac stays off the internet.
struct AgentState: Decodable, Hashable, Sendable {
    /// Schema version. Bumped if the shape ever changes so an old app and a
    /// new hook (or the reverse) can disagree loudly rather than silently.
    let v: Int
    /// tmux `#{pane_id}` the agent is running in — the record's real identity.
    let pane: String
    /// tmux session name. What the app matches on, since that's its unit.
    let session: String
    /// `claude-code` or `codex`.
    let agent: String
    /// `working` | `awaiting` | `idle` | `error`.
    let state: String
    /// Unix time the current turn started.
    let since: Int
    /// Unix time this record was written.
    let updated: Int
    let sessionID: String?
    /// The turn's final text, straight from the hook payload.
    ///
    /// Worth more than it looks: scraping this off the pane means undoing the
    /// hard-wrapping Claude Code already applied, which is the most fragile
    /// part of the screen-reading path.
    let lastMessage: String?
    /// What it's waiting to be told, when `state` is `awaiting`.
    let question: String?

    enum CodingKeys: String, CodingKey {
        case v, pane, session, agent, state, since, updated
        case sessionID = "session_id"
        case lastMessage = "last_message"
        case question
    }

    var kind: AgentKind { agent == "codex" ? .codex : .claudeCode }

    /// Parses the JSONL the app reads in one shot (`cat ~/.remotessh/state/*.json`).
    ///
    /// A malformed line is skipped, not fatal: one bad record must not blind
    /// the app to every other session.
    static func parse(_ jsonl: String) -> [AgentState] {
        jsonl.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(AgentState.self, from: data)
        }
    }

    /// Whether this record can still be believed.
    ///
    /// A hook can't publish "the agent died": `kill -9` and a closed lid fire
    /// nothing, so a `working` record would otherwise claim work is happening
    /// forever. Superset solves the same problem with a manual "Clear Status"
    /// button; the app doesn't need one, because it already asks tmux what the
    /// pane is running and can simply notice the claim is no longer possible.
    ///
    /// - Parameter command: tmux `#{pane_current_command}` for that session.
    func isStale(command: String, now: Date = Date()) -> Bool {
        if v != 1 { return true }
        // Nothing is running a turn in a pane that has gone back to a shell.
        if state == "working" || state == "awaiting" {
            let isAgent = ClaudeCodeRecogniser.isClaudeCode(command: command)
                || CodexRecogniser.isGenericInterpreter(command: command)
            if !isAgent { return true }
        }
        // A day-old record survived a reboot of something. Don't trust it.
        return now.timeIntervalSince1970 - Double(updated) > 24 * 60 * 60
    }

    /// The app's own status type, so the UI doesn't care which source it came
    /// from.
    func status(now: Date = Date()) -> AgentStatus {
        let elapsed = Self.elapsedText(seconds: Int(now.timeIntervalSince1970) - since)
        switch state {
        case "working":
            return AgentStatus(agent: kind, activity: .working(verb: "Working"),
                               source: .hook, elapsed: elapsed)
        case "awaiting":
            return AgentStatus(agent: kind, activity: .awaitingApproval,
                               source: .hook, task: question)
        case "error":
            return AgentStatus(agent: kind, activity: .failed,
                               source: .hook, task: "The turn ended with an API error.")
        default:
            return AgentStatus(agent: kind, activity: .idle, source: .hook,
                               lastMessage: lastMessage)
        }
    }

    /// `7m 3s`, the way the agents render it themselves — so a banner fed by a
    /// hook and one fed by the screen read identically.
    static func elapsedText(seconds: Int) -> String? {
        guard seconds > 0, seconds < 24 * 60 * 60 else { return nil }
        let m = seconds / 60, s = seconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
