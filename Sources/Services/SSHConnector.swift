import Foundation
import Citadel
import NIOSSH
import Crypto

/// Shared connect + authentication logic used by both the polling path
/// (`RemoteShell`) and the interactive terminal path (`SSHTerminalRunner`).
///
/// Every function here is nonisolated; the non-Sendable `SSHClient` it returns
/// must stay within a single nonisolated async scope.
enum SSHConnector {
    static func connect(config: SSHConnectionConfig, credential: SSHCredential) async throws -> SSHClient {
        try await SSHClient.connect(
            host: config.host,
            port: config.port,
            authenticationMethod: try authenticationMethod(config: config, credential: credential),
            hostKeyValidator: .acceptAnything(), // TODO(phase5): pin/trust host keys
            reconnect: .never
        )
    }

    static func authenticationMethod(config: SSHConnectionConfig, credential: SSHCredential) throws -> SSHAuthenticationMethod {
        switch credential {
        case .password(let password):
            return .passwordBased(username: config.username, password: password)
        case .privateKey(let openSSHText):
            let key = try Curve25519.Signing.PrivateKey(sshEd25519: openSSHText)
            return .ed25519(username: config.username, privateKey: key)
        }
    }
}
