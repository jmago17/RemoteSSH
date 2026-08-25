import Foundation
import UIKit

/// Registers this device with APNs and hands the token to the Mac.
///
/// **Why the Mac and not a server.** The hooks that know when an agent finished
/// already run there, and the Mac can talk to APNs itself — it only needs
/// HTTP/2 and an ES256 JWT, which URLSession and CryptoKit provide. So the
/// token travels the way everything else does: over the SSH connection the app
/// already opens. Nothing to host, and the `.p8` key never leaves the Mac.
///
/// **Why not a third-party push service.** With one of those the notification
/// belongs to *their* app, so the badge lands on their icon rather than on
/// RemoteSSH's. That doesn't follow from a missing API field but from who
/// receives the push.
@MainActor
enum APNSRegistration {

    /// Where the token is written on the Mac. `apns-push` reads it there.
    static let remotePath = "~/.remotessh/apns-token.json"

    /// The APNs host this token is valid against.
    ///
    /// Follows from how the binary was signed, not from a preference: Debug
    /// builds get sandbox tokens, TestFlight and App Store builds production
    /// ones. Crossing them fails with `BadDeviceToken` and nothing arrives, so
    /// it is recorded next to the token rather than guessed at send time.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// What the app knows about its own push registration. Surfaced in
    /// Settings, because the first version of this failed **silently** and
    /// left no way to tell "iOS never gave us a token" apart from "the upload
    /// to the Mac failed" — which is exactly the distinction needed to fix it.
    enum Status {
        case notRegistered
        case failed(String)
        case pendingUpload
        case uploaded(environment: String)

        var summary: String {
            switch self {
            case .notRegistered: return "Not registered yet"
            case .failed(let reason): return "Registration failed: \(reason)"
            case .pendingUpload: return "Token held, not yet sent to the Mac"
            case .uploaded(let environment): return "Sent to the Mac (\(environment))"
            }
        }
    }

    static var status: Status {
        let defaults = UserDefaults.standard
        if let error = defaults.string(forKey: errorKey) { return .failed(error) }
        if defaults.string(forKey: uploadedKey) != nil { return .uploaded(environment: environment) }
        if defaults.string(forKey: pendingKey) != nil { return .pendingUpload }
        return .notRegistered
    }

    static func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Keeps the token whether or not anything can send it right now.
    ///
    /// **This is the bug the first version had.** The token was uploaded
    /// straight from the delegate callback, behind a `guard` on having SSH
    /// credentials loaded — and iOS hands the token over within a moment of
    /// launch, often before the model has read them. The guard failed, the
    /// token was dropped, and nothing ever retried: a race that could lose
    /// every single time. Now it is stored first and uploaded whenever the app
    /// next has a connection to use.
    static func remember(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: pendingKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
    }

    static func registrationFailed(_ error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: errorKey)
    }

    /// Sends the stored token to the Mac, if there is one and it hasn't gone up
    /// already. Safe to call on every refresh: it does nothing in the common
    /// case.
    static func uploadPendingIfNeeded(
        config: SSHConnectionConfig,
        credential: SSHCredential
    ) async {
        let defaults = UserDefaults.standard
        guard let token = defaults.string(forKey: pendingKey),
              token != defaults.string(forKey: uploadedKey)
        else { return }

        let json = #"{"token":"\#(token)","environment":"\#(environment)"}"#
        do {
            try await TmuxService().writeRemoteFile(json, to: remotePath, config: config, credential: credential)
            defaults.set(token, forKey: uploadedKey)
        } catch {
            // Recorded rather than swallowed, and left pending so the next
            // refresh tries again.
            defaults.set("Upload failed: \(error.localizedDescription)", forKey: errorKey)
        }
    }

    private static let pendingKey = "apnsTokenPending"
    private static let uploadedKey = "apnsTokenUploaded"
    private static let errorKey = "apnsRegistrationError"
}
