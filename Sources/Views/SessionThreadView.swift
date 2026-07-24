import SwiftUI

/// The "thread" view for a session, with a Peek/Attach toggle:
/// - **Attach**: interactive SwiftTerm terminal (`tmux attach`).
/// - **Peek**: read-only scrollback capture (no attach, doesn't disturb the pane).
struct SessionThreadView: View {
    let session: TmuxSession
    @Bindable var model: SessionListModel

    @State private var mode: Mode = .attach

    enum Mode: String, CaseIterable, Identifiable {
        case attach = "Attach"
        case peek = "Peek"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch mode {
            case .attach:
                TerminalScreen(session: session, config: model.config)
            case .peek:
                ScrollbackView(session: session, model: model)
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.markRead(session.name) }
    }
}
