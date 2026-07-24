import Foundation
import Citadel
import NIOCore

/// Owns a short-lived SSH connection and runs one-shot `exec` commands over it.
/// The polling model opens a connection, runs a batch of tmux commands, then
/// disconnects — iOS suspends background sockets, so we never hold one open.
///
/// Deliberately **not** Sendable: `SSHClient` is non-Sendable, so an instance
/// must live entirely within a single nonisolated async scope (see
/// `TmuxService`). It must never be stored on an actor or captured across an
/// isolation boundary.
final class RemoteShell {
    private var client: SSHClient?

    private let config: SSHConnectionConfig
    private let credential: SSHCredential

    init(config: SSHConnectionConfig, credential: SSHCredential) {
        self.config = config
        self.credential = credential
    }

    func connect() async throws {
        guard client == nil else { return }
        client = try await SSHConnector.connect(config: config, credential: credential)
    }

    /// Runs a command and returns its stdout as UTF-8 text.
    func run(_ command: String) async throws -> String {
        guard let client else { throw RemoteShellError.notConnected }
        var buffer = try await client.executeCommand(command)
        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        return String(decoding: bytes, as: UTF8.self)
    }

    func disconnect() async {
        try? await client?.close()
        client = nil
    }

    enum RemoteShellError: LocalizedError {
        case notConnected

        var errorDescription: String? {
            switch self {
            case .notConnected: return "SSH connection is not established."
            }
        }
    }
}
