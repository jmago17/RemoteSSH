import Foundation
import NIOCore
import NIOSSH
import Crypto

/// Trust-on-first-use host-key pinning. On the first connection to a host we
/// record its key fingerprint; every later connection must match, or we refuse
/// (a changed key can mean a man-in-the-middle). Replaces `acceptAnything()`.
final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let hostID: String

    init(host: String, port: Int) {
        self.hostID = HostKeyStore.id(host: host, port: port)
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let fingerprint = HostKeyStore.fingerprint(of: hostKey)

        if let known = HostKeyStore.storedFingerprint(for: hostID) {
            if known == fingerprint {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyMismatch(hostID: hostID))
            }
        } else {
            HostKeyStore.store(fingerprint: fingerprint, for: hostID) // trust on first use
            validationCompletePromise.succeed(())
        }
    }
}

/// Persistence + fingerprinting for pinned host keys.
enum HostKeyStore {
    static func id(host: String, port: Int) -> String { "\(host):\(port)" }

    private static func key(_ hostID: String) -> String { "hostkey-\(hostID)" }

    static func fingerprint(of hostKey: NIOSSHPublicKey) -> String {
        var buffer = ByteBuffer()
        _ = hostKey.write(to: &buffer)
        let bytes = buffer.readBytes(length: buffer.readableBytes) ?? []
        return SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    static func storedFingerprint(for hostID: String) -> String? {
        UserDefaults.standard.string(forKey: key(hostID))
    }

    static func store(fingerprint: String, for hostID: String) {
        UserDefaults.standard.set(fingerprint, forKey: key(hostID))
    }

    /// Forget the pinned key so the next connection re-trusts (use after a
    /// legitimate host reinstall / key rotation).
    static func resetTrust(host: String, port: Int) {
        UserDefaults.standard.removeObject(forKey: key(id(host: host, port: port)))
    }

    static func hasTrustedKey(host: String, port: Int) -> Bool {
        storedFingerprint(for: id(host: host, port: port)) != nil
    }
}

struct HostKeyMismatch: LocalizedError {
    let hostID: String
    var errorDescription: String? {
        "The host key for \(hostID) has changed — this could be a man-in-the-middle. If you reinstalled the Mac or rotated its key, reset the trusted host key in Settings."
    }
}
