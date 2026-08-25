import SwiftUI
import UIKit

/// Exists only to receive the APNs device token — SwiftUI has no equivalent
/// hook, so the token arrives through the old delegate whether we like it or
/// not.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by the scene once the model exists, since the token can land before
    /// or after SwiftUI has built anything.
    @MainActor static var onToken: ((Data) -> Void)?
    /// Held for the case where the token arrives first.
    @MainActor static var pendingToken: Data?

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Task { @MainActor in
            if let handler = Self.onToken { handler(token) } else { Self.pendingToken = token }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Nothing to do: without a token the Mac keeps using the transport it
        // was using before, so this degrades rather than breaks.
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
                    AppDelegate.onToken = { token in
                        Task { await model.storeAPNSToken(token) }
                    }
                    if let pending = AppDelegate.pendingToken {
                        AppDelegate.pendingToken = nil
                        Task { await model.storeAPNSToken(pending) }
                    }
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
