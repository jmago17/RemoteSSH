import Foundation
import Citadel
import NIOCore
import NIOSSH

/// Terminal dimensions in character cells.
struct TerminalSize: Sendable, Equatable {
    var cols: Int
    var rows: Int
}

/// Wraps a non-Sendable value so it can be captured by concurrent child tasks.
/// Safe here because the wrapped `TTYStdinWriter` funnels every write through a
/// single NIO `Channel`, which is itself thread-safe.
struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Drives an interactive `tmux attach` over a persistent SSH PTY channel.
///
/// Entirely nonisolated: the non-Sendable `SSHClient`/PTY writer live only
/// inside this async scope. It talks to the `@MainActor` `TerminalSession`
/// exclusively through Sendable streams and a `@Sendable` output callback.
enum SSHTerminalRunner {
    /// Runs until the remote program exits, the task is cancelled, or an error
    /// occurs. `onOutput` is called (off the main actor) with each stdout/stderr
    /// chunk from the host.
    static func run(
        config: SSHConnectionConfig,
        credential: SSHCredential,
        startupCommand: String,
        initialSize: TerminalSize,
        userInput: AsyncStream<[UInt8]>,
        resizes: AsyncStream<TerminalSize>,
        onOutput: @escaping @Sendable ([UInt8]) -> Void
    ) async throws {
        let client = try await SSHConnector.connect(config: config, credential: credential)
        do {
            let request = SSHChannelRequestEvent.PseudoTerminalRequest(
                wantReply: true,
                term: "xterm-256color",
                terminalCharacterWidth: initialSize.cols,
                terminalRowHeight: initialSize.rows,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0,
                terminalModes: SSHTerminalModes([:])
            )

            try await client.withPTY(request) { inbound, outbound in
                let writer = UncheckedSendableBox(outbound)

                // Replace the login shell with tmux so a clean detach closes the
                // channel and ends the session.
                try await outbound.write(ByteBuffer(string: startupCommand + "\n"))

                // Forward keystrokes and resize events concurrently with the
                // output pump below.
                let forwarding = Task {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await bytes in userInput {
                                try? await writer.value.write(ByteBuffer(bytes: bytes))
                            }
                        }
                        group.addTask {
                            for await size in resizes {
                                try? await writer.value.changeSize(
                                    cols: size.cols, rows: size.rows,
                                    pixelWidth: 0, pixelHeight: 0
                                )
                            }
                        }
                    }
                }
                defer { forwarding.cancel() }

                // Pump host output into the terminal until the channel closes.
                for try await chunk in inbound {
                    switch chunk {
                    case .stdout(let buffer), .stderr(let buffer):
                        onOutput(Array(buffer.readableBytesView))
                    }
                }
            }

            try? await client.close()
        } catch {
            try? await client.close()
            throw error
        }
    }
}
