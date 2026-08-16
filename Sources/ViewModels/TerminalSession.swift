import Foundation
import Observation

/// Main-actor bridge between the SwiftUI terminal view and the nonisolated
/// `SSHTerminalRunner`. Keystrokes and resizes go out via Sendable streams;
/// host output comes back through `onData`, invoked on the main actor.
@MainActor
@Observable
final class TerminalSession {
    enum Phase: Equatable {
        case connecting
        case live
        case closed(String?)
    }

    private(set) var phase: Phase = .connecting

    /// Set by the terminal view to receive host output (feeds the emulator).
    @ObservationIgnored var onData: (([UInt8]) -> Void)?

    private let config: SSHConnectionConfig
    private let credential: SSHCredential
    private let startupCommand: String

    private let userInput: AsyncStream<[UInt8]>
    private let userInputCont: AsyncStream<[UInt8]>.Continuation
    private let resizes: AsyncStream<TerminalSize>
    private let resizeCont: AsyncStream<TerminalSize>.Continuation

    private var runTask: Task<Void, Never>?

    init(config: SSHConnectionConfig, credential: SSHCredential, startupCommand: String) {
        self.config = config
        self.credential = credential
        self.startupCommand = startupCommand
        (userInput, userInputCont) = AsyncStream.makeStream()
        (resizes, resizeCont) = AsyncStream.makeStream()
    }

    func start(initialSize: TerminalSize) {
        guard runTask == nil else { return }
        phase = .connecting

        let config = self.config
        let credential = self.credential
        let startupCommand = self.startupCommand
        let userInput = self.userInput
        let resizes = self.resizes

        runTask = Task { [weak self] in
            do {
                try await SSHTerminalRunner.run(
                    config: config,
                    credential: credential,
                    startupCommand: startupCommand,
                    initialSize: initialSize,
                    userInput: userInput,
                    resizes: resizes,
                    onOutput: { bytes in
                        Task { @MainActor in self?.deliver(bytes) }
                    }
                )
                await self?.finish(error: nil)
            } catch {
                await self?.finish(error: Self.friendlyMessage(for: error))
            }
        }
    }

    /// Nonisolated so SwiftTerm's delegate (which fires on the main thread but
    /// through a nonisolated protocol) can forward keystrokes directly. Only
    /// touches the Sendable stream continuation.
    nonisolated func sendUserInput(_ bytes: [UInt8]) {
        userInputCont.yield(bytes)
    }

    nonisolated func resize(_ size: TerminalSize) {
        resizeCont.yield(size)
    }

    /// Sends a well-known control sequence (for on-screen special keys that the
    /// soft keyboard can't easily produce).
    nonisolated func sendKey(_ key: SpecialKey) {
        sendUserInput(key.bytes)
    }

    /// Every key the iOS soft keyboard can't produce (or can't produce without
    /// three taps): control codes, navigation, and the punctuation buried
    /// behind the numeric/symbol planes.
    ///
    /// `String`-backed so slot assignments can round-trip through `AppStorage`.
    enum SpecialKey: String, CaseIterable, Identifiable, Sendable {
        // Control / editing
        case escape, tab, shiftTab, enter, backspace
        // Control codes
        case ctrlA, ctrlC, ctrlD, ctrlE, ctrlK, ctrlL, ctrlR, ctrlU, ctrlW, ctrlZ
        // Navigation
        case up, down, left, right, home, end, pageUp, pageDown
        // tmux
        case detach, tmuxPrefix
        // Punctuation the soft keyboard buries
        case tilde, pipe, slash, backslash, dash, underscore, backtick
        case dollar, star, hash, caret, ampersand, percent
        case braceOpen, braceClose, bracketOpen, bracketClose
        case angleOpen, angleClose, parenOpen, parenClose
        case quoteSingle, quoteDouble, semicolon, colon, equals, plus, question, at, bang

        var id: String { rawValue }

        var bytes: [UInt8] {
            switch self {
            case .escape:    return [0x1b]
            case .tab:       return [0x09]
            case .shiftTab:  return [0x1b, 0x5b, 0x5a]   // ESC [ Z
            case .enter:     return [0x0d]
            case .backspace: return [0x7f]

            case .ctrlA: return [0x01]
            case .ctrlC: return [0x03]
            case .ctrlD: return [0x04]
            case .ctrlE: return [0x05]
            case .ctrlK: return [0x0b]
            case .ctrlL: return [0x0c]
            case .ctrlR: return [0x12]
            case .ctrlU: return [0x15]
            case .ctrlW: return [0x17]
            case .ctrlZ: return [0x1a]

            case .up:       return [0x1b, 0x5b, 0x41]    // ESC [ A
            case .down:     return [0x1b, 0x5b, 0x42]
            case .right:    return [0x1b, 0x5b, 0x43]
            case .left:     return [0x1b, 0x5b, 0x44]
            case .home:     return [0x1b, 0x5b, 0x48]
            case .end:      return [0x1b, 0x5b, 0x46]
            case .pageUp:   return [0x1b, 0x5b, 0x35, 0x7e]
            case .pageDown: return [0x1b, 0x5b, 0x36, 0x7e]

            case .detach:      return [0x02, 0x64]       // C-b d
            case .tmuxPrefix:  return [0x02]             // C-b

            case .tilde:        return [0x7e]
            case .pipe:         return [0x7c]
            case .slash:        return [0x2f]
            case .backslash:    return [0x5c]
            case .dash:         return [0x2d]
            case .underscore:   return [0x5f]
            case .backtick:     return [0x60]
            case .dollar:       return [0x24]
            case .star:         return [0x2a]
            case .hash:         return [0x23]
            case .caret:        return [0x5e]
            case .ampersand:    return [0x26]
            case .percent:      return [0x25]
            case .braceOpen:    return [0x7b]
            case .braceClose:   return [0x7d]
            case .bracketOpen:  return [0x5b]
            case .bracketClose: return [0x5d]
            case .angleOpen:    return [0x3c]
            case .angleClose:   return [0x3e]
            case .parenOpen:    return [0x28]
            case .parenClose:   return [0x29]
            case .quoteSingle:  return [0x27]
            case .quoteDouble:  return [0x22]
            case .semicolon:    return [0x3b]
            case .colon:        return [0x3a]
            case .equals:       return [0x3d]
            case .plus:         return [0x2b]
            case .question:     return [0x3f]
            case .at:           return [0x40]
            case .bang:         return [0x21]
            }
        }

        /// What the cap shows.
        var label: String {
            switch self {
            case .escape: return "esc"
            case .tab: return "tab"
            case .shiftTab: return "\u{21e7}\u{21e5}"
            case .enter: return "\u{21b5}"
            case .backspace: return "\u{232b}"
            case .ctrlA: return "^A"
            case .ctrlC: return "^C"
            case .ctrlD: return "^D"
            case .ctrlE: return "^E"
            case .ctrlK: return "^K"
            case .ctrlL: return "^L"
            case .ctrlR: return "^R"
            case .ctrlU: return "^U"
            case .ctrlW: return "^W"
            case .ctrlZ: return "^Z"
            case .up: return "\u{2191}"
            case .down: return "\u{2193}"
            case .left: return "\u{2190}"
            case .right: return "\u{2192}"
            case .home: return "home"
            case .end: return "end"
            case .pageUp: return "pgup"
            case .pageDown: return "pgdn"
            case .detach: return "\u{2303}b d"
            case .tmuxPrefix: return "\u{2303}b"
            case .tilde: return "~"
            case .pipe: return "|"
            case .slash: return "/"
            case .backslash: return "\\"
            case .dash: return "-"
            case .underscore: return "_"
            case .backtick: return "`"
            case .dollar: return "$"
            case .star: return "*"
            case .hash: return "#"
            case .caret: return "^"
            case .ampersand: return "&"
            case .percent: return "%"
            case .braceOpen: return "{"
            case .braceClose: return "}"
            case .bracketOpen: return "["
            case .bracketClose: return "]"
            case .angleOpen: return "<"
            case .angleClose: return ">"
            case .parenOpen: return "("
            case .parenClose: return ")"
            case .quoteSingle: return "'"
            case .quoteDouble: return "\""
            case .semicolon: return ";"
            case .colon: return ":"
            case .equals: return "="
            case .plus: return "+"
            case .question: return "?"
            case .at: return "@"
            case .bang: return "!"
            }
        }

        /// VoiceOver / picker name.
        var spoken: String {
            switch self {
            case .escape: return "Escape"
            case .tab: return "Tab"
            case .shiftTab: return "Shift Tab"
            case .enter: return "Return"
            case .backspace: return "Backspace"
            case .ctrlA: return "Control A"
            case .ctrlC: return "Control C"
            case .ctrlD: return "Control D"
            case .ctrlE: return "Control E"
            case .ctrlK: return "Control K"
            case .ctrlL: return "Control L"
            case .ctrlR: return "Control R"
            case .ctrlU: return "Control U"
            case .ctrlW: return "Control W"
            case .ctrlZ: return "Control Z"
            case .up: return "Up Arrow"
            case .down: return "Down Arrow"
            case .left: return "Left Arrow"
            case .right: return "Right Arrow"
            case .home: return "Home"
            case .end: return "End"
            case .pageUp: return "Page Up"
            case .pageDown: return "Page Down"
            case .detach: return "Detach"
            case .tmuxPrefix: return "tmux Prefix"
            case .tilde: return "Tilde"
            case .pipe: return "Pipe"
            case .slash: return "Slash"
            case .backslash: return "Backslash"
            case .dash: return "Dash"
            case .underscore: return "Underscore"
            case .backtick: return "Backtick"
            case .dollar: return "Dollar"
            case .star: return "Asterisk"
            case .hash: return "Hash"
            case .caret: return "Caret"
            case .ampersand: return "Ampersand"
            case .percent: return "Percent"
            case .braceOpen: return "Open Brace"
            case .braceClose: return "Close Brace"
            case .bracketOpen: return "Open Bracket"
            case .bracketClose: return "Close Bracket"
            case .angleOpen: return "Less Than"
            case .angleClose: return "Greater Than"
            case .parenOpen: return "Open Paren"
            case .parenClose: return "Close Paren"
            case .quoteSingle: return "Single Quote"
            case .quoteDouble: return "Double Quote"
            case .semicolon: return "Semicolon"
            case .colon: return "Colon"
            case .equals: return "Equals"
            case .plus: return "Plus"
            case .question: return "Question Mark"
            case .at: return "At Sign"
            case .bang: return "Exclamation"
            }
        }

        /// Grouping for the expanded panel and the slot picker.
        enum Group: String, CaseIterable, Identifiable {
            case navigation = "Navigation"
            case control = "Control"
            case symbols = "Symbols"
            case tmux = "tmux"
            var id: String { rawValue }
        }

        var group: Group {
            switch self {
            case .up, .down, .left, .right, .home, .end, .pageUp, .pageDown:
                return .navigation
            case .escape, .tab, .shiftTab, .enter, .backspace,
                 .ctrlA, .ctrlC, .ctrlD, .ctrlE, .ctrlK, .ctrlL,
                 .ctrlR, .ctrlU, .ctrlW, .ctrlZ:
                return .control
            case .detach, .tmuxPrefix:
                return .tmux
            default:
                return .symbols
            }
        }

        static func group(_ g: Group) -> [SpecialKey] {
            allCases.filter { $0.group == g }
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        userInputCont.finish()
        resizeCont.finish()
    }

    // MARK: Private

    private func deliver(_ bytes: [UInt8]) {
        if phase == .connecting { phase = .live }
        onData?(bytes)
    }

    private func finish(error: String?) {
        phase = .closed(error)
    }

    /// A closed/EOF channel just means the session detached or ended — show the
    /// neutral "Session ended" rather than a raw NIO error. Real auth/network
    /// failures keep their message.
    private static func friendlyMessage(for error: Error) -> String? {
        let text = "\(error)"
        if text.contains("ChannelError") || text.contains("EOF") || text.localizedCaseInsensitiveContains("closed") {
            return nil
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
