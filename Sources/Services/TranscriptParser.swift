import Foundation

// MARK: - Model

/// One turn in the conversational reading of a tmux pane.
///
/// Three kinds, deliberately: what *I* typed, what the *machine* answered, and
/// a `raw` escape for everything the parser refuses to guess at.
struct TranscriptTurn: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// A line the user typed at a shell prompt.
        case command
        /// Everything the machine printed until the next prompt.
        case output
        /// Structure wasn't recognised — shown verbatim, monospaced, and
        /// labelled as such. Never split into invented turns.
        case raw
    }

    /// Position in this parse. Stable for the lifetime of one `Transcript`,
    /// which is all `ForEach` needs — a re-parse replaces the whole array.
    let id: Int
    let kind: Kind
    let text: String

    /// Only meaningful on `.output`. A *guess* from textual signals, never a
    /// certainty: `capture-pane` carries no exit status.
    var isLikelyError: Bool = false

    /// The real exit code, on the rare occasion the shell renders one into the
    /// following prompt (p10k / oh-my-zsh print `✘ 1`). This is the only
    /// non-heuristic error signal available.
    var exitCode: Int?

    var lineCount: Int {
        text.isEmpty ? 0 : text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}

/// The parsed pane, plus an honest account of how well it went.
struct Transcript: Hashable, Sendable {
    var turns: [TranscriptTurn]
    /// `nil` when the pane really was parsed into turns. Otherwise the reason
    /// the parser gave up and fell back to a single `.raw` block.
    var fallback: Fallback?
    /// Set when the pane is running a coding agent. The frame is still shown
    /// raw — we summarise its state, we never re-render its body.
    var agent: AgentStatus?

    enum Fallback: Hashable, Sendable {
        /// Nothing in the pane at all.
        case emptyPane
        /// tmux says a full-screen program owns the pane (vim, htop, less).
        case fullScreenProgram(String)
        /// A coding agent — recognised, summarised, and shown as a live frame.
        case agent(AgentKind)
        /// No prompt signature could be inferred from the live prompt line.
        case noPromptFound
        /// A signature was found but it didn't survive the confidence gate.
        case lowConfidence

        /// Shown above the raw block, so the user knows *why* they're looking
        /// at a dump instead of a conversation.
        var explanation: String {
            switch self {
            case .emptyPane:
                return "This session hasn't printed anything yet."
            case .fullScreenProgram(let command):
                let name = command.isEmpty ? "A full-screen program" : "`\(command)`"
                return "\(name) is running in this pane, so it's showing a screen, not a log. Open the terminal to interact with it."
            case .agent(let kind):
                return "Live screen from \(kind.displayName). Shown as-is — it wraps its own text, so re-flowing it would break paths and commands."
            case .noPromptFound:
                return "No shell prompt could be recognised in this pane. Showing it raw rather than guessing which command produced what."
            case .lowConfidence:
                return "The prompt pattern here wasn't consistent enough to trust. Showing the pane raw rather than inventing turns."
            }
        }
    }

    var isStructured: Bool { fallback == nil }

    static let empty = Transcript(turns: [], fallback: .emptyPane)
}

/// What one `capture-pane` call brought back, plus the two facts about the pane
/// that save the parser from guessing (see `TmuxService.capturePane`).
struct PaneSnapshot: Hashable, Sendable {
    var text: String
    /// tmux `#{alternate_on}` — 1 while a curses app owns the screen.
    var alternateScreen: Bool
    /// tmux `#{pane_current_command}` — the foreground process.
    var currentCommand: String
    /// tmux `#{pane_title}` — Claude Code publishes the current task here.
    var paneTitle: String
    /// tmux `#{pane_height}` — rows in the pane, i.e. how much of `text` is
    /// the *screen* rather than scrollback. See `visibleScreen`.
    var paneHeight: Int
    /// Raw `ps -t <pane_tty> -o stat=,args=` output: every process attached to
    /// the pane's terminal, one per line, each prefixed with its state.
    ///
    /// **Why the tty and not `#{pane_pid}`.** `pane_pid` is the *root* process
    /// of the pane — the shell tmux started. When someone opens a pane and
    /// types `codex`, the agent is a child, and asking `ps` about the pane pid
    /// answers `-zsh`. (It only looks right when the pane was created with the
    /// agent as its command, which is exactly how the first harness built it,
    /// which is why this shipped broken.) The tty is shared by the whole
    /// process group, so it finds the child.
    ///
    /// Only fetched when `currentCommand` is a generic interpreter, because
    /// that's the only case where the process name doesn't already say what
    /// the pane is. Empty when it wasn't asked for, or when `ps` said nothing.
    var foregroundProcesses: String
    /// What the agent's own lifecycle hooks last published for this pane, when
    /// there is anything. The authority on state when present — see
    /// `AgentState`.
    var agentState: AgentState?

    init(
        text: String,
        alternateScreen: Bool = false,
        currentCommand: String = "",
        paneTitle: String = "",
        paneHeight: Int = 0,
        foregroundProcesses: String = "",
        agentState: AgentState? = nil
    ) {
        self.text = text
        self.alternateScreen = alternateScreen
        self.currentCommand = currentCommand
        self.paneTitle = paneTitle
        self.paneHeight = paneHeight
        self.foregroundProcesses = foregroundProcesses
        self.agentState = agentState
    }

    /// Just the part of `text` that is on screen right now.
    ///
    /// **This distinction is load-bearing, and getting it wrong is a lie the
    /// user can see.** The capture is 2000 lines deep so the chat transcript
    /// has history to show, but an agent's *state* — is it working, is it
    /// waiting for me — is a property of the current screen only. Searching the
    /// whole capture for "is there a question on screen" finds every question
    /// the agent ever asked, including ones answered an hour ago, and reports a
    /// pane that is quietly idle as "waiting for your answer".
    ///
    /// The agent's own redraw is what makes this work: an answered prompt is
    /// gone from the screen and survives only in scrollback. Verified against a
    /// live pane — `capture-pane -p` and the last `#{pane_height}` lines of
    /// `capture-pane -p -J -S -2000` came back identical.
    ///
    /// Falls back to the whole text when tmux didn't tell us the height, which
    /// is the old behaviour rather than an empty screen.
    var visibleScreen: String {
        guard paneHeight > 0 else { return text }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > paneHeight else { return text }
        return lines.suffix(paneHeight).joined(separator: "\n")
    }

    private static let shells: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh", "login", "tmux",
    ]

    /// True when the foreground process is a shell — i.e. the pane plausibly
    /// holds a prompt/command/output log. An empty value means tmux didn't tell
    /// us, and we give the text the benefit of the doubt.
    var isShell: Bool {
        guard !currentCommand.isEmpty else { return true }
        // Login shells arrive as `-zsh`.
        let name = currentCommand.hasPrefix("-")
            ? String(currentCommand.dropFirst())
            : currentCommand
        return Self.shells.contains(name)
    }
}

// MARK: - Parser

/// Turns a raw `tmux capture-pane` dump into chat turns.
///
/// **This is a heuristic, and it is wrong sometimes.** `capture-pane -p` returns
/// flat text with no command markers — no OSC 133 semantic prompts, no exit
/// codes, no separation between what was typed and what was printed. Everything
/// below is inference, and the guiding rule is: *a false positive is far worse
/// than a missed one*. Splitting an output in half and attributing its second
/// half to the wrong command is a lie; showing an honest unstructured block is
/// merely less pretty. When in doubt the parser degrades to `.raw`.
///
/// The whole type is pure — `String` in, values out. No networking, no SwiftUI,
/// no shared state — so it can run off the main actor and be reasoned about in
/// isolation.
enum TranscriptParser {

    // MARK: Prompt signature

    /// The inferred shape of *this session's* prompt.
    ///
    /// Deliberately not "recognise any prompt": generic patterns match `$` in a
    /// shell script, `>` in an XML diff, `%` in a printf format. Instead the
    /// signature is learned from one reliable sample — the live prompt sitting
    /// at the bottom of the pane waiting for input — and only lines resembling
    /// *that* are treated as prompts.
    struct PromptSignature: Hashable, Sendable {
        /// The sigil printed right before the cursor: `$`, `%`, `#`, `>`, `❯`…
        let anchor: Character
        /// Everything before the anchor on the live prompt line: `josu@mac:~/dev`.
        let preAnchor: String
        /// Lines the prompt occupies — 2 for powerlevel10k's `╭─…` / `╰─❯`.
        let height: Int

        /// Sigils that essentially never occur in ordinary command output, so
        /// the glyph alone is signature enough.
        static let safeAnchors: Set<Character> = ["❯", "➜", "»", "λ", "▶", "▸", "→", "✦"]
        /// Sigils that appear constantly in real output — these need the
        /// pre-anchor text to corroborate them.
        static let riskyAnchors: Set<Character> = ["$", "%", "#", ">"]

        var isSafeAnchor: Bool { Self.safeAnchors.contains(anchor) }

        /// How alike the pre-anchor text must be for a line to count as a
        /// prompt. Exotic glyphs need no corroboration; `$` needs a lot.
        var requiredSimilarity: Double { isSafeAnchor ? 0 : 0.6 }

        /// Prompt lines needed (beyond the live one) before the structure is
        /// believed. One sighting of `❯` is convincing; one sighting of `$`
        /// is a coin flip, so those need a real pattern.
        var requiredMatches: Int { isSafeAnchor ? 1 : 3 }
    }

    // MARK: Entry points

    /// Parses a pane, using what tmux told us about it.
    static func parse(_ snapshot: PaneSnapshot) -> Transcript {
        let lines = normalise(snapshot.text)
        guard !lines.isEmpty else { return .empty }

        // Claude Code trips the curses wire below, but it is the app's most
        // common session and its frame is already conversational. Recognise it
        // first and attach a status summary. The body still goes through as a
        // raw frame: Claude hard-wraps to the pane width, so reflowing it into
        // bubbles would corrupt paths and commands (`Pl` + `atforms`).
        // A hook record outranks anything read off the screen: it is the
        // process saying what it is doing, rather than the app inferring it
        // from how the process happens to draw itself this week. The screen is
        // still read afterwards, but only to *decorate* — see `enrich`.
        if let state = snapshot.agentState, !state.isStale(command: snapshot.currentCommand) {
            var t = raw(lines, because: .agent(state.kind))
            t.agent = enrich(state.status(), fromScreen: snapshot)
            return t
        }

        if ClaudeCodeRecogniser.isClaudeCode(command: snapshot.currentCommand) {
            var t = raw(lines, because: .agent(.claudeCode))
            t.agent = ClaudeCodeRecogniser.status(
                text: snapshot.visibleScreen,
                paneTitle: snapshot.paneTitle
            )
            return t
        }

        // Codex, same deal — but it can't be recognised from the process name,
        // which is a bare `node`. See `CodexRecogniser` for why detection leans
        // on the process arguments instead. This has to come before the curses
        // check below for the *opposite* reason to Claude Code: Codex stays on
        // the normal screen (`alternate_on` is 0), so it would otherwise fall
        // through to `isShell` being false and get written off as a full-screen
        // program named `node`.
        if CodexRecogniser.isCodex(
            command: snapshot.currentCommand,
            foregroundProcesses: snapshot.foregroundProcesses,
            text: snapshot.text
        ) {
            var t = raw(lines, because: .agent(.codex))
            t.agent = CodexRecogniser.status(
                text: snapshot.visibleScreen,
                paneTitle: snapshot.paneTitle
            )
            return t
        }

        // Layer 1 — the reliable check. A curses app owns the screen, so the
        // dump is a *frame*, not a log. Never try to slice a frame: htop alone
        // contains numbers, words and paths, and is a false-positive factory.
        if snapshot.alternateScreen || !snapshot.isShell {
            return raw(lines, because: .fullScreenProgram(snapshot.currentCommand))
        }

        guard let signature = inferSignature(from: lines) else {
            // Layer 2 — the textual fallback, for when tmux couldn't be asked.
            if looksLikeFullScreenFrame(lines) {
                return raw(lines, because: .fullScreenProgram(snapshot.currentCommand))
            }
            return raw(lines, because: .noPromptFound)
        }

        let promptIndices = lines.indices.filter { promptBody(of: lines[$0], matching: signature) != nil }

        guard passesConfidenceGate(promptIndices, in: lines, signature: signature) else {
            return raw(lines, because: .lowConfidence)
        }

        return Transcript(turns: buildTurns(lines, promptIndices: promptIndices, signature: signature), fallback: nil)
    }

    /// Borrows the cosmetic details the screen has and the hooks don't.
    ///
    /// A hook knows *that* a turn is running; the pane knows Claude Code is
    /// currently calling it "Hullaballooing", how long it says it has been at
    /// it, and how many tokens it has read. Those are worth showing, but only
    /// when the screen agrees with the hook about the state — if they disagree,
    /// the hook wins outright and the screen's guess is discarded rather than
    /// blended into a banner that is half one thing and half another.
    private static func enrich(_ status: AgentStatus, fromScreen snapshot: PaneSnapshot) -> AgentStatus {
        guard case .working = status.activity else { return status }
        let screen: AgentStatus
        switch status.agent {
        case .claudeCode:
            screen = ClaudeCodeRecogniser.status(text: snapshot.visibleScreen, paneTitle: snapshot.paneTitle)
        case .codex:
            screen = CodexRecogniser.status(text: snapshot.visibleScreen, paneTitle: snapshot.paneTitle)
        }
        guard case .working = screen.activity else { return status }

        var enriched = status
        enriched.activity = screen.activity      // the real verb
        enriched.elapsed = screen.elapsed ?? status.elapsed
        enriched.tokens = screen.tokens
        enriched.detail = screen.detail
        if enriched.task == nil { enriched.task = screen.task }
        return enriched
    }

    /// Convenience for plain text with nothing known about the pane.
    static func parse(_ text: String) -> Transcript {
        parse(PaneSnapshot(text: text))
    }

    /// The same parse, guaranteed to run off the caller's actor.
    ///
    /// `parse` is synchronous and `nonisolated`, so calling it straight from the
    /// `@MainActor` would run it *on* the main thread — a couple of thousand
    /// lines of scanning is enough to drop frames. `@concurrent` pins it to the
    /// concurrent executor regardless of the module's default-isolation
    /// settings, so this stays true if the project ever turns on Approachable
    /// Concurrency (which flips plain `nonisolated async` back to running on the
    /// caller's actor).
    @concurrent
    static func parsed(_ snapshot: PaneSnapshot) async -> Transcript {
        parse(snapshot)
    }

    // MARK: Normalisation

    /// Splits into lines, strips ANSI escapes, and right-trims each line.
    ///
    /// `capture-pane -p` without `-e` shouldn't contain escapes at all, but
    /// panes carry leftovers — a program that printed a colour sequence into a
    /// log, a partially-drawn frame. Strip them before anything else, or the
    /// invisible bytes break both the prompt match and the similarity score.
    /// Trailing blank lines are pane padding and carry no meaning.
    static func normalise(_ text: String) -> [String] {
        var lines = stripANSI(text)
            .components(separatedBy: "\n")
            .map { line -> String in
                var trimmed = Substring(line)
                while let last = trimmed.last, last == " " || last == "\t" || last == "\r" {
                    trimmed = trimmed.dropLast()
                }
                return String(trimmed)
            }
        while lines.last?.isEmpty == true { lines.removeLast() }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        return lines
    }

    /// Removes CSI (`ESC [ … final`), OSC (`ESC ] … BEL | ESC \`) and stray
    /// two-character escapes, plus control characters other than tab/newline.
    static func stripANSI(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count)

        var iterator = text.makeIterator()
        var pending: Character?

        while let character = pending ?? iterator.next() {
            pending = nil

            guard character == "\u{1B}" else {
                // Keep newlines and tabs; drop the rest of C0 (BEL, backspace,
                // carriage returns left over from progress bars).
                if character == "\n" || character == "\t" || !character.isControlCharacter {
                    out.append(character)
                }
                continue
            }

            guard let next = iterator.next() else { break }
            switch next {
            case "[":
                // CSI: parameters and intermediates, then a final byte @…~
                while let byte = iterator.next() {
                    if let ascii = byte.asciiValue, (0x40...0x7E).contains(ascii) { break }
                }
            case "]":
                // OSC: runs until BEL or ST (ESC \)
                while let byte = iterator.next() {
                    if byte == "\u{07}" { break }
                    if byte == "\u{1B}" {
                        if let terminator = iterator.next(), terminator != "\\" { pending = terminator }
                        break
                    }
                }
            case "P", "X", "^", "_":
                // DCS / SOS / PM / APC — same ST-terminated shape as OSC.
                while let byte = iterator.next() {
                    if byte == "\u{1B}" {
                        if let terminator = iterator.next(), terminator != "\\" { pending = terminator }
                        break
                    }
                }
            default:
                break // Two-character escape; both consumed.
            }
        }
        return out
    }

    // MARK: Signature inference

    /// Learns the prompt shape from the bottom of the pane.
    ///
    /// The last non-empty line is almost always the live prompt waiting for
    /// input — this session's own prompt, empty, handed to us for free. That is
    /// a far better sample than mining the dump for a common prefix: the most
    /// common prompt segment is often the *working directory*, which changes,
    /// so the literal common prefix between two prompt lines is frequently the
    /// empty string.
    static func inferSignature(from lines: [String]) -> PromptSignature? {
        guard let last = lines.last, !last.isEmpty else { return nil }

        let anchor: Character
        let preAnchor: String

        if let trailing = last.last, isAnchor(trailing) {
            // The common case: an empty prompt waiting for input.
            anchor = trailing
            preAnchor = String(last.dropLast())
        } else if let match = firstAnchor(in: last) {
            // The user left something half-typed at the prompt. Very common —
            // and without this the whole pane would go unstructured just
            // because the bottom line has characters after the sigil.
            anchor = match.anchor
            preAnchor = match.preAnchor
        } else {
            return nil
        }

        // A bare `$` or `>` with nothing in front of it is indistinguishable
        // from output. Refuse the signature rather than shred a build log.
        if PromptSignature.riskyAnchors.contains(anchor),
           preAnchor.trimmingCharacters(in: .whitespaces).isEmpty {
            return nil
        }

        // Two-line prompts (powerlevel10k's `╭─ … ` / `╰─❯ `): if the line above
        // the anchor line opens a box, the prompt is a block and the command
        // lives after the anchor on its second line.
        var height = 1
        if lines.count >= 2, let opener = lines[lines.count - 2].first,
           "╭┌╒╓┏".contains(opener) {
            height = 2
        }

        return PromptSignature(anchor: anchor, preAnchor: preAnchor, height: height)
    }

    private static func isAnchor(_ character: Character) -> Bool {
        PromptSignature.safeAnchors.contains(character) || PromptSignature.riskyAnchors.contains(character)
    }

    /// Finds the leftmost anchor followed by a space — the sigil of a prompt
    /// that already has a partly-typed command after it.
    private static func firstAnchor(in line: String) -> (anchor: Character, preAnchor: String)? {
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let after = line.index(after: index)
            if isAnchor(character), after < line.endIndex, line[after] == " " {
                return (character, String(line[line.startIndex..<index]))
            }
            index = after
        }
        return nil
    }

    /// If `line` is a prompt under `signature`, returns the text after the
    /// anchor — i.e. the typed command. Returns `nil` when it isn't a prompt.
    static func promptBody(of line: String, matching signature: PromptSignature) -> String? {
        var index = line.startIndex
        while let anchorIndex = line[index...].firstIndex(of: signature.anchor) {
            let after = line.index(after: anchorIndex)
            // A prompt sigil is followed by a space or the end of the line; it
            // is never glued to the command. This alone rejects `$PATH`,
            // `${VAR}`, `100%done` and `->`.
            let isDetached = after == line.endIndex || line[after] == " "
            if isDetached {
                let pre = String(line[line.startIndex..<anchorIndex])
                if similarity(pre, signature.preAnchor) >= signature.requiredSimilarity {
                    return String(line[after...]).trimmingCharacters(in: .whitespaces)
                }
            }
            guard after < line.endIndex else { break }
            index = after
        }
        return nil
    }

    /// How alike two prompt bodies are: the longer of their common prefix and
    /// their common suffix, over the length of the shorter string.
    ///
    /// This absorbs the *variable* parts of a prompt while still demanding that
    /// a stable chunk actually be there — and it has to work from both ends,
    /// because prompts vary at both. The cwd varies at the end
    /// (`josu@mac:~/dev` → `josu@mac:~/other`), so the prefix carries it; the
    /// exit-status marker varies at the *start* (`josu@mac:~` → `✘ 1 josu@mac:~`),
    /// so only the suffix survives there. Taking the better of the two covers
    /// both without loosening either.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }

        var prefix = 0
        for (left, right) in zip(a, b) {
            if left != right { break }
            prefix += 1
        }
        var suffix = 0
        for (left, right) in zip(a.reversed(), b.reversed()) {
            if left != right { break }
            suffix += 1
        }
        return Double(max(prefix, suffix)) / Double(min(a.count, b.count))
    }

    // MARK: Confidence

    /// Two independent ways the inferred signature can be caught lying. Both
    /// must pass, otherwise the whole pane degrades to `.raw`.
    ///
    /// A third check was considered and rejected: capping *prompt density* (the
    /// share of lines that look like prompts) at ~40%. It sounds right, and it
    /// is wrong — a session of `cd`, `export`, `mkdir` and other quiet commands
    /// is legitimately 60-100% prompt lines, and the cap threw those away.
    /// Verified against the harness: it was the single thing breaking ordinary
    /// short-output scrollbacks. The work it was supposed to do — stopping `>`
    /// from matching an XML dump — is already done, and done better, by
    /// requiring a non-empty pre-anchor plus three corroborating matches.
    static func passesConfidenceGate(
        _ promptIndices: [Int],
        in lines: [String],
        signature: PromptSignature
    ) -> Bool {
        // 1 — corroboration. The live prompt at the bottom is the sample we
        // learned from, so it can't vouch for itself.
        let corroborating = promptIndices.filter { $0 < lines.count - signature.height }
        guard corroborating.count >= signature.requiredMatches else { return false }

        // 2 — do the extracted "commands" look like commands? When a signature
        // is really matching output, most of them won't.
        let commands = corroborating.compactMap { promptBody(of: lines[$0], matching: signature) }
        guard !commands.isEmpty else { return false }
        return Double(commands.filter(isPlausibleCommand).count) / Double(commands.count) >= 0.8
    }

    /// A typed command starts with something command-shaped and isn't absurdly
    /// long. An empty string counts — pressing Enter at a prompt is legitimate.
    static func isPlausibleCommand(_ command: String) -> Bool {
        guard !command.isEmpty else { return true }
        guard command.count < 500 else { return false }
        guard let first = command.first else { return true }
        return first.isLetter || first.isNumber || "_./~$(-\"'".contains(first)
    }

    // MARK: Turn construction

    private static func buildTurns(
        _ lines: [String],
        promptIndices: [Int],
        signature: PromptSignature
    ) -> [TranscriptTurn] {
        var turns: [TranscriptTurn] = []
        var nextID = 0

        func append(_ kind: TranscriptTurn.Kind, _ text: String, isLikelyError: Bool = false, exitCode: Int? = nil) {
            guard !text.isEmpty else { return }
            turns.append(
                TranscriptTurn(id: nextID, kind: kind, text: text, isLikelyError: isLikelyError, exitCode: exitCode)
            )
            nextID += 1
        }

        // A `-S -2000` window usually starts mid-output. That head has no parent
        // command, so it must never be glued onto the first one we find.
        if let first = promptIndices.first, first > 0 {
            append(.raw, lines[0..<first].joined(separator: "\n"))
        }

        for (position, promptIndex) in promptIndices.enumerated() {
            let bodyStart = promptIndex + signature.height
            let nextPromptIndex = position + 1 < promptIndices.count ? promptIndices[position + 1] : lines.count

            // The live prompt at the bottom isn't a turn. If it carries text,
            // that's a half-typed command that was never run — showing it as
            // something the user executed would be a lie.
            if nextPromptIndex >= lines.count && bodyStart >= lines.count { continue }

            guard let command = promptBody(of: lines[promptIndex], matching: signature) else { continue }

            let outputLines = bodyStart < nextPromptIndex
                ? Array(lines[bodyStart..<nextPromptIndex])
                : []

            // Per-block degradation: one bad turn drops to raw without taking
            // the rest of the pane down with it.
            guard isPlausibleCommand(command) else {
                append(.raw, ([lines[promptIndex]] + outputLines).joined(separator: "\n"))
                continue
            }

            let exitCode = position + 1 < promptIndices.count
                ? exitCode(fromPrompt: lines[promptIndices[position + 1]], signature: signature)
                : nil

            // The code rides on the command too, so a command that prints
            // nothing at all (`false`, a failed `cd`) still shows it failed.
            if !command.isEmpty { append(.command, command, exitCode: exitCode) }

            let output = trimBlankEdges(outputLines).joined(separator: "\n")
            guard !output.isEmpty else { continue }

            append(
                .output,
                output,
                isLikelyError: exitCode.map { $0 != 0 } ?? looksLikeError(outputLines),
                exitCode: exitCode
            )
        }

        return turns
    }

    private static func trimBlankEdges(_ lines: [String]) -> [String] {
        var result = lines
        while result.last?.isEmpty == true { result.removeLast() }
        while result.first?.isEmpty == true { result.removeFirst() }
        return result
    }

    // MARK: Error signals

    /// Error markers, checked only in the first two lines of the output.
    ///
    /// Scanning the whole block for "error" would flag every build log, every
    /// `grep error`, and every test summary that prints "0 failed". Restricting
    /// it to the head is what keeps this useful rather than noise.
    static func looksLikeError(_ outputLines: [String]) -> Bool {
        let head = trimBlankEdges(outputLines).prefix(2)
        for line in head {
            let lowered = line.lowercased()
            if lowered.contains("command not found")
                || lowered.contains("no such file or directory")
                || lowered.contains("permission denied")
                || lowered.contains("operation not permitted")
                || lowered.contains("segmentation fault") {
                return true
            }
            let leading = line.drop(while: { $0 == " " }).lowercased()
            if leading.hasPrefix("error:") || leading.hasPrefix("fatal:") || leading.hasPrefix("panic:")
                || leading.hasPrefix("traceback (most recent call last)") {
                return true
            }
        }
        return false
    }

    /// Reads a real exit status off the *following* prompt, for shells that
    /// render one (powerlevel10k's `✘ 1`, oh-my-zsh's `1 ↵`). The only signal
    /// here that isn't guesswork — so when it's present it wins over
    /// `looksLikeError`.
    static func exitCode(fromPrompt line: String, signature: PromptSignature) -> Int? {
        guard let anchorIndex = line.firstIndex(of: signature.anchor) else { return nil }
        let head = Array(line[line.startIndex..<anchorIndex])

        // `✘ 1` — powerlevel10k's status segment.
        for (position, character) in head.enumerated() where "✘✗⨯".contains(character) {
            var index = position + 1
            while index < head.count, head[index] == " " { index += 1 }
            var digits = ""
            while index < head.count, head[index].isNumber {
                digits.append(head[index])
                index += 1
            }
            if let code = Int(digits) { return code }
        }

        // `1 ↵` — oh-my-zsh's.
        for (position, character) in head.enumerated() where character == "↵" {
            var index = position - 1
            while index >= 0, head[index] == " " { index -= 1 }
            var digits = ""
            while index >= 0, head[index].isNumber {
                digits.insert(head[index], at: digits.startIndex)
                index -= 1
            }
            if let code = Int(digits) { return code }
        }

        return nil
    }

    // MARK: Full-screen detection (textual fallback)

    /// Backstop for when tmux couldn't be asked about `alternate_on`.
    ///
    /// Only consulted after signature inference has already failed, so it can
    /// afford to be loose: box-drawing glyphs, vim's tilde gutter, a pager
    /// footer. Anything matching here is shown raw either way; the only thing
    /// this changes is which explanation the user reads.
    static func looksLikeFullScreenFrame(_ lines: [String]) -> Bool {
        let tail = lines.suffix(50)
        guard !tail.isEmpty else { return false }

        var boxLines = 0
        var tildeGutter = 0
        for line in tail {
            if line.contains(where: { "│┌┐└┘─├┤┬┴┼╔╗╚╝║═╠╣".contains($0) }) { boxLines += 1 }
            if line == "~" || line.hasPrefix("~ ") { tildeGutter += 1 }
            if line.hasSuffix("-- INSERT --") || line.hasSuffix("(END)") || line == ":" { return true }
        }
        return boxLines >= 3 || tildeGutter >= 3
    }

    // MARK: Fallback

    private static func raw(_ lines: [String], because fallback: Transcript.Fallback) -> Transcript {
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return .empty }
        return Transcript(turns: [TranscriptTurn(id: 0, kind: .raw, text: text)], fallback: fallback)
    }
}

private extension Character {
    /// C0 controls and DEL — the bytes that survive escape stripping and would
    /// otherwise render as boxes.
    var isControlCharacter: Bool {
        guard let ascii = asciiValue else { return false }
        return ascii < 0x20 || ascii == 0x7F
    }
}
