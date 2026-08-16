import SwiftUI

@main
struct RemoteSSHApp: App {
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
