import SwiftUI

@main
struct RemoteSSHApp: App {
    @State private var model = SessionListModel()

    var body: some Scene {
        WindowGroup {
            SessionListView(model: model)
        }
    }
}
