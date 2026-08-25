import Foundation
import UIKit

/// Registers this device with APNs and hands the token to the Mac.
///
/// **Why the Mac and not a server.** The hooks that know when an agent finished
/// already run on the Mac, and the Mac can talk to APNs itself — it only needs
/// HTTP/2 and an ES256 JWT, which URLSession and CryptoKit provide. So the
/// token travels the way everything else in this app travels: written over the
/// SSH connection the app already opens. No relay, nothing to host, and the
/// `.p8` key never leaves the Mac.
///
/// **Why not keep using a third-party push service.** With one of those, the
/// notification belongs to *their* app, so the badge lands on their icon rather
/// than on RemoteSSH's. That isn't a missing API field, it follows from who
/// receives the push — the only way to badge our own icon is to own the push.
@MainActor
enum APNSRegistration {

    /// Where the token is written on the Mac. `apns-push` reads it from there.
    static let remotePath = "~/.remotessh/apns-token.json"

    /// The APNs host a token is valid against.
    ///
    /// Tied to how the binary was signed, not to a preference: a Debug build
    /// gets a sandbox token, and TestFlight/App Store builds get production
    /// ones. Sending a sandbox token to the production host fails with
    /// `BadDeviceToken` and nothing arrives, so this is recorded alongside the
    /// token rather than guessed at send time.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Stores the token on the Mac, once per token value.
    ///
    /// Tokens change rarely (reinstall, restore, occasionally an OS update) but
    /// they do change, so this compares against the last one uploaded instead
    /// of uploading on every launch.
    static func upload(
        deviceToken: Data,
        config: SSHConnectionConfig,
        credential: SSHCredential
    ) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard token != UserDefaults.standard.string(forKey: uploadedKey) else { return }

        let json = #"{"token":"\#(token)","environment":"\#(environment)"}"#
        do {
            try await TmuxService().writeRemoteFile(json, to: remotePath, config: config, credential: credential)
            UserDefaults.standard.set(token, forKey: uploadedKey)
        } catch {
            // Left unrecorded on purpose: the next launch retries, and a failed
            // upload only means notifications keep arriving the old way.
        }
    }

    private static let uploadedKey = "apnsTokenUploaded"
}
