import SwiftUI

/// The "chat list": one row per tmux session, with the active host's identity
/// sitting under the title as the way into Settings.
struct SessionListView: View {
    @Bindable var model: SessionListModel
    @State private var showingSettings = false
    @State private var renameTarget: TmuxSession?
    @State private var renameText = ""
    @State private var showingNewSession = false
    @State private var newSessionName = ""

    @State private var path: [TmuxSession] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !model.isConfigured {
                    unconfiguredState
                } else if model.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .background(Theme.bg)
            .navigationDestination(for: TmuxSession.self) { session in
                TerminalScreen(session: session, model: model)
            }
            .navigationTitle("Sessions")
            .phosphorNavigationBar(opaque: false)
            .toolbar {
                if model.isConfigured {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            newSessionName = ""
                            showingNewSession = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New Session")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                Task { await model.restoreSessions() }
                            } label: {
                                Label("Restore Saved Sessions", systemImage: "arrow.clockwise.circle")
                            }
                            if model.config.canWakeOnLAN {
                                Button {
                                    model.wakeOnLAN()
                                } label: {
                                    Label("Wake Mac (LAN)", systemImage: "power")
                                }
                            }
                            Button {
                                Task { await model.wakeDisplay() }
                            } label: {
                                Label("Wake Display", systemImage: "sun.max")
                            }
                            Divider()
                            Button {
                                showingSettings = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("More")
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                if model.isRefreshing {
                    ToolbarItem(placement: .topBarLeading) {
                        ProgressView().tint(Theme.textTertiary)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(model: model)
            }
            .alert("New Session", isPresented: $showingNewSession) {
                TextField("Session name", text: $newSessionName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { }
                Button("Create") {
                    let name = newSessionName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task { await model.createSession(name) }
                }
            } message: {
                Text("Creates a detached tmux session on \(model.config.host).")
            }
            .alert("Rename Session", isPresented: renameBinding) {
                TextField("New name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Rename") {
                    if let target = renameTarget {
                        let newName = renameText
                        Task { await model.rename(target.name, to: newName) }
                    }
                    renameTarget = nil
                }
            }
        }
        .tint(Theme.link)
        .task {
            model.reloadConfig()
            model.startPolling()
        }
        .onChange(of: model.pendingOpenSession) { _, name in
            guard let name else { return }
            if !path.contains(where: { $0.name == name }) {
                path.append(TmuxSession(name: name, isAttached: false, created: .now,
                                        lastActivity: .now, preview: "", contentHash: 0))
            }
            model.pendingOpenSession = nil
        }
        .onDisappear { model.stopPolling() }
    }

    private var sessionList: some View {
        List {
            Button {
                showingSettings = true
            } label: {
                HostChip(label: hostLabel, isConnected: model.errorMessage == nil)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))

            if let error = model.errorMessage {
                errorBanner(error)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
            }

            ForEach(model.sessions) { session in
                // A plain button rather than a NavigationLink: the row carries
                // its own trailing unread dot, so the system disclosure
                // chevron would be noise.
                Button {
                    path.append(session)
                } label: {
                    SessionRowView(session: session)
                }
                .buttonStyle(RowButtonStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparatorTint(Theme.hairline)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await model.kill(session.name) }
                    } label: {
                        Label("Kill", systemImage: "trash")
                    }
                    Button {
                        renameTarget = session
                        renameText = session.name
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(Theme.surfaceRaised)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .refreshable { await model.refresh() }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.warn)
                .padding(.top, 1)
            Text(message)
                .font(.mono(11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .fill(Theme.warn.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .stroke(Theme.warn.opacity(0.26), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = model.errorMessage {
            ContentUnavailableView {
                Label("Connection Problem", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error).font(.mono(12))
            } actions: {
                if model.config.canWakeOnLAN {
                    Button("Wake Mac") { model.wakeOnLAN() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.live)
                        .foregroundStyle(Theme.onLive)
                }
                Button("Retry") { Task { await model.refresh() } }
                Button("Settings") { showingSettings = true }
            }
            .tint(Theme.link)
        } else {
            ContentUnavailableView {
                Label("No Sessions", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("No tmux sessions are running on \(model.config.host).")
            } actions: {
                Button("Restore Saved Sessions") { Task { await model.restoreSessions() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.live)
                    .foregroundStyle(Theme.onLive)
                Button("Refresh") { Task { await model.refresh() } }
            }
            .tint(Theme.link)
        }
    }

    private var unconfiguredState: some View {
        ContentUnavailableView {
            Label("Set Up a Connection", systemImage: "network")
        } description: {
            Text("Add your Mac's host, username, and a credential to start listing tmux sessions.")
        } actions: {
            Button("Open Settings") { showingSettings = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.live)
                .foregroundStyle(Theme.onLive)
        }
        .tint(Theme.link)
    }

    private var hostLabel: String {
        let config = model.config
        guard config.isComplete else { return "No host configured" }
        return "\(config.username)@\(config.host)"
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }
}
