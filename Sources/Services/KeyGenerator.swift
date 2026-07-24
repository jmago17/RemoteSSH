import Foundation
import Crypto

/// Generates an ed25519 key pair in-app. The private key is stored (as base64
/// raw bytes) in the Keychain like any other credential; the public key is
/// shown in OpenSSH `authorized_keys` format for the user to add to their Mac.
enum KeyGenerator {
    struct GeneratedKey {
        /// base64 of the 32-byte private key — stored as the `.privateKey` secret.
        let privateSecret: String
        /// `ssh-ed25519 AAAA... comment` line for ~/.ssh/authorized_keys.
        let publicKeyLine: String
    }

    static func generate(comment: String = "RemoteSSH") -> GeneratedKey {
        let key = Curve25519.Signing.PrivateKey()
        return GeneratedKey(
            privateSecret: key.rawRepresentation.base64EncodedString(),
            publicKeyLine: openSSHPublicLine(key.publicKey, comment: comment)
        )
    }

    /// Builds the OpenSSH public-key line: `ssh-ed25519 <base64 wire blob> comment`.
    static func openSSHPublicLine(_ publicKey: Curve25519.Signing.PublicKey, comment: String) -> String {
        let keyType = "ssh-ed25519"
        var blob = Data()
        func writeSSHString(_ data: Data) {
            var length = UInt32(data.count).bigEndian
            withUnsafeBytes(of: &length) { blob.append(contentsOf: $0) }
            blob.append(data)
        }
        writeSSHString(Data(keyType.utf8))
        writeSSHString(publicKey.rawRepresentation) // 32 bytes
        return "\(keyType) \(blob.base64EncodedString()) \(comment)"
    }
}
