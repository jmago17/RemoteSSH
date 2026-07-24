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
            hostKeyValidator: .custom(TOFUHostKeyValidator(host: config.host, port: config.port)),
            reconnect: .never
        )
    }

    static func authenticationMethod(config: SSHConnectionConfig, credential: SSHCredential) throws -> SSHAuthenticationMethod {
        switch credential {
        case .password(let password):
            return .passwordBased(username: config.username, password: password)
        case .privateKey(let secret):
            let key = try ed25519Key(from: secret)
            return .ed25519(username: config.username, privateKey: key)
        }
    }

    /// Accepts either an OpenSSH private-key file (pasted) or the base64 raw
    /// bytes produced by in-app key generation.
    private static func ed25519Key(from secret: String) throws -> Curve25519.Signing.PrivateKey {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("BEGIN OPENSSH PRIVATE KEY") {
            return try Curve25519.Signing.PrivateKey(sshEd25519: trimmed)
        }
        if let raw = Data(base64Encoded: trimmed), raw.count == 32 {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        }
        // Fall back to OpenSSH parsing (e.g. armored text without exact header match).
        return try Curve25519.Signing.PrivateKey(sshEd25519: trimmed)
    }
}
