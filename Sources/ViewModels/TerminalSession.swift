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

    enum SpecialKey {
        case shiftTab   // CSI Z — back-tab (e.g. Claude Code "shift+tab to cycle")
        case escape
        case tab
        case ctrlC
        case detach     // tmux prefix (Ctrl-b) then d

        var bytes: [UInt8] {
            switch self {
            case .shiftTab: return [0x1b, 0x5b, 0x5a]   // ESC [ Z
            case .escape:   return [0x1b]
            case .tab:      return [0x09]
            case .ctrlC:    return [0x03]
            case .detach:   return [0x02, 0x64]         // C-b d
            }
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
