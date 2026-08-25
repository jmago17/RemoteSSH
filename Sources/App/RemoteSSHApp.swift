import SwiftUI
import UIKit

/// Exists only to receive the APNs device token — SwiftUI has no equivalent
/// hook, so the token arrives through the old delegate whether we like it or
/// not.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        // Stored unconditionally. Whether anything can upload it right now is
        // a separate question, answered on the next refresh — see
        // `APNSRegistration.remember`.
        Task { @MainActor in APNSRegistration.remember(deviceToken: token) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Recorded, not swallowed. Silence here is what made the first
        // diagnosis guesswork: "iOS never gave us a token" and "the upload
        // failed" looked identical from the Mac.
        Task { @MainActor in APNSRegistration.registrationFailed(error) }
    }
}

@main
struct RemoteSSHApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SessionListModel()
    @State private var router = NotificationRouter()

    var body: some Scene {
        WindowGroup {
            SessionListView(model: model)
                // The identity is a dark, terminal-native one end to end —
                // the attach view is a real terminal, not a themed surface.
                .preferredColorScheme(.dark)
                .tint(Theme.link)
                .task {
                    // Wire notifications: taps/links open a session; ntfy
                    // messages become iOS notifications.
                    model.startCloudSync()
                    router.configure()
                    router.onOpenSession = { model.requestOpen($0) }
                    model.onAttention = { session, body in
                        router.postAttention(session: session, body: body)
                    }
                    model.onRequestNotificationAuth = { router.requestAuthorization() }

                    // Push registration. The token goes to the Mac, which is
                    // what actually sends the notifications.
                    APNSRegistration.register()
                }
                .onOpenURL { url in
                    // remotessh://open/<session>
                    if let session = NtfySubscriber.session(fromClick: url.absoluteString) {
                        model.requestOpen(session)
                    }
                }
        }
    }
}
