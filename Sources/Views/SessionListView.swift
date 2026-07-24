import SwiftUI

/// The "chat list": one row per tmux session.
struct SessionListView: View {
    @Bindable var model: SessionListModel
    @State private var showingSettings = false
    @State private var renameTarget: TmuxSession?
    @State private var renameText = ""
    @State private var showingNewSession = false
    @State private var newSessionName = ""

    var body: some View {
        NavigationStack {
            Group {
                if !model.isConfigured {
                    unconfiguredState
                } else if model.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
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
                }
                if model.isRefreshing {
                    ToolbarItem(placement: .topBarLeading) {
                        ProgressView()
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
        .task {
            model.reloadConfig()
            model.startPolling()
        }
        .onDisappear { model.stopPolling() }
    }

    private var sessionList: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
            ForEach(model.sessions) { session in
                NavigationLink {
                    SessionThreadView(session: session, model: model)
                } label: {
                    SessionRowView(session: session)
                }
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
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await model.refresh() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sessions", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("No tmux sessions are running on \(model.config.host).")
        } actions: {
            Button("Refresh") { Task { await model.refresh() } }
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
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }
}
