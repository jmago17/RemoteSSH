import SwiftUI

/// A session's "thread": a full interactive SwiftTerm terminal bound to
/// `tmux attach -t <name>` over a live SSH PTY.
struct TerminalScreen: View {
    let session: TmuxSession
    @Bindable var model: SessionListModel

    @State private var terminal: TerminalSession?
    @State private var setupError: String?
    @State private var generation = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let terminal {
                // A new id on reconnect forces a fresh SwiftTerm view + attach.
                TerminalHostView(session: terminal).id(generation)
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
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    terminal?.sendKey(.shiftTab)
                } label: {
                    Text("⇧⇥").font(.body.monospaced())
                }
                .accessibilityLabel("Send Shift-Tab")
                .disabled(terminal == nil)

                Menu {
                    Button("Esc") { terminal?.sendKey(.escape) }
                    Button("Tab") { terminal?.sendKey(.tab) }
                    Button("Ctrl-C") { terminal?.sendKey(.ctrlC) }
                    Divider()
                    Button("Detach (⌃b d)") { terminal?.sendKey(.detach) }
                } label: {
                    Image(systemName: "keyboard")
                }
                .disabled(terminal == nil)
            }
        }
        .onAppear {
            model.markRead(session.name)
            setup()
        }
        .onDisappear { terminal?.stop() }
        .onChange(of: scenePhase) { _, phase in
            // iOS suspends the socket in the background; re-attach on return so
            // the pane catches up near-seamlessly.
            if phase == .active, case .closed = terminal?.phase { reconnect() }
        }
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
            VStack(spacing: 12) {
                Spacer()
                Label(message ?? "Session ended", systemImage: "bolt.horizontal.circle")
                    .font(.footnote)
                    .foregroundStyle(message == nil ? Color.secondary : Color.orange)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                Button {
                    reconnect()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 24)
            }
        case .live:
            EmptyView()
        }
    }

    private func reconnect() {
        terminal?.stop()
        terminal = nil
        setupError = nil
        generation += 1
        setup()
    }

    private func setup() {
        guard terminal == nil, setupError == nil else { return }
        guard let credential = SettingsStore().loadCredential(for: model.config) else {
            setupError = "No stored credential."
            return
        }
        // `env` injects Homebrew onto PATH; `exec` replaces the shell so a
        // clean tmux detach closes the channel.
        let command = "exec env \(TmuxService.pathPrefix) tmux attach -t \(TmuxService.quote(session.name))"
        terminal = TerminalSession(config: model.config, credential: credential, startupCommand: command)
    }
}
