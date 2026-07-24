import SwiftUI

/// Manage saved hosts: pick the active one, add, edit, delete.
struct HostListView: View {
    @Bindable var model: SessionListModel

    @State private var editingHost: SSHConnectionConfig?
    @State private var addingHost = false

    var body: some View {
        List {
            ForEach(model.hosts) { host in
                Button {
                    model.selectHost(host.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name.isEmpty ? host.host : host.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("\(host.username)@\(host.host):\(host.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if host.id == model.config.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                        }
                    }
                }
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
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("Hosts")
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
                }
            }
        }
        .sheet(item: $editingHost) { host in
            HostEditorView(model: model, host: host)
        }
        .sheet(isPresented: $addingHost) {
            HostEditorView(model: model, host: nil)
        }
    }
}
