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
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await self?.finish(error: message)
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
}
