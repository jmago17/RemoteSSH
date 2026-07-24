import SwiftUI

/// Phase 1 "thread" view: a read-only capture of the pane scrollback.
/// Phase 2 will replace this with an interactive SwiftTerm attach.
struct ScrollbackView: View {
    let session: TmuxSession
    @Bindable var model: SessionListModel

    @State private var content = ""
    @State private var isLoading = true
    @State private var loadError: String?

    private let tmux = TmuxService()

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            if isLoading && content.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if let loadError {
                Text(loadError)
                    .foregroundStyle(.orange)
                    .padding()
            } else {
                Text(content.isEmpty ? "(empty pane)" : content)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .background(Color(.systemBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload")
            }
        }
        .task {
            model.markRead(session.name)
            await load()
        }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        guard let credential = SettingsStore().loadCredential(for: model.config) else {
            loadError = "No stored credential."
            return
        }
        do {
            let text = try await tmux.captureScrollback(
                session: session.name,
                config: model.config,
                credential: credential
            )
            content = text
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
