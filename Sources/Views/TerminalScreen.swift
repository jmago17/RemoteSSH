import SwiftUI

/// Interactive "attach" mode: a full SwiftTerm terminal bound to
/// `tmux attach -t <name>` over a live SSH PTY.
struct TerminalScreen: View {
    let session: TmuxSession
    let config: SSHConnectionConfig

    @State private var terminal: TerminalSession?
    @State private var setupError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let terminal {
                TerminalHostView(session: terminal)
                statusOverlay(terminal)
            } else if let setupError {
                ContentUnavailableView {
                    Label("Can't Attach", systemImage: "xmark.octagon")
                } description: {
                    Text(setupError)
                }
            } else {
                ProgressView()
            }
        }
        .onAppear(perform: setup)
        .onDisappear { terminal?.stop() }
    }

    @ViewBuilder
    private func statusOverlay(_ terminal: TerminalSession) -> some View {
        switch terminal.phase {
        case .connecting:
            VStack {
                Spacer()
                Label("Connecting…", systemImage: "dot.radiowaves.left.and.right")
                    .font(.footnote)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        case .closed(let message):
            VStack {
                Spacer()
                Label(message ?? "Session ended", systemImage: "bolt.horizontal.circle")
                    .font(.footnote)
                    .foregroundStyle(message == nil ? Color.secondary : Color.orange)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        case .live:
            EmptyView()
        }
    }

    private func setup() {
        guard terminal == nil, setupError == nil else { return }
        guard let credential = SettingsStore().loadCredential(for: config) else {
            setupError = "No stored credential."
            return
        }
        let command = "exec tmux attach -t \(TmuxService.quote(session.name))"
        terminal = TerminalSession(config: config, credential: credential, startupCommand: command)
    }
}
