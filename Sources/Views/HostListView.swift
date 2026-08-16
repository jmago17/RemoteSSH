import SwiftUI

/// Manage saved hosts: pick the active one, add, edit, delete.
struct HostListView: View {
    @Bindable var model: SessionListModel

    @State private var editingHost: SSHConnectionConfig?
    @State private var addingHost = false

    var body: some View {
        List {
            Section {
                ForEach(model.hosts) { host in
                    Button {
                        model.selectHost(host.id)
                    } label: {
                        hostRow(host)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.deleteHost(host.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingHost = host
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(Theme.surfaceRaised)
                    }
                }
            } header: {
                SectionHeaderText("Saved")
            } footer: {
                Text("Tap a host to make it active — the session list reloads against it. Swipe to edit or delete.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .listRowBackground(Theme.surface)
        }
        .phosphorForm()
        .navigationTitle("Hosts")
        .navigationBarTitleDisplayMode(.inline)
        .phosphorNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addingHost = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Host")
            }
        }
        .overlay {
            if model.hosts.isEmpty {
                ContentUnavailableView {
                    Label("No Hosts", systemImage: "server.rack")
                } description: {
                    Text("Add a Mac to connect to.")
                } actions: {
                    Button("Add Host") { addingHost = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.live)
                        .foregroundStyle(Theme.onLive)
                }
                .background(Theme.bg)
            }
        }
        .sheet(item: $editingHost) { host in
            HostEditorView(model: model, host: host)
        }
        .sheet(isPresented: $addingHost) {
            HostEditorView(model: model, host: nil)
        }
    }

    private func hostRow(_ host: SSHConnectionConfig) -> some View {
        let isActive = host.id == model.config.id
        return HStack(spacing: 12) {
            SessionTile(
                name: host.name.isEmpty ? host.host : host.name,
                isAttached: isActive,
                size: 36,
                punchOut: Theme.surface,
                showsPresence: false
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(host.name.isEmpty ? host.host : host.name)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.text)
                Text("\(host.username)@\(host.host):\(host.port)")
                    .font(.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 8)

            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.live)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
