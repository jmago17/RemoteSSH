import SwiftUI

/// The "chat list": one row per tmux session.
struct SessionListView: View {
    @Bindable var model: SessionListModel
    @State private var showingSettings = false
    @State private var renameTarget: TmuxSession?
    @State private var renameText = ""
    @State private var showingNewSession = false
    @State private var newSessionName = ""

    @State private var path: [TmuxSession]

    init(model: SessionListModel) {
        self.model = model
        #if DEBUG
        // Deep-link straight into a session's terminal for testing: launch with
        // `--seed-test-config` and env REMOTESSH_OPEN=<name>.
        if let name = ProcessInfo.processInfo.environment["REMOTESSH_OPEN"] {
            _path = State(initialValue: [TmuxSession(name: name, isAttached: false,
                                                     created: .now, lastActivity: .now,
                                                     preview: "", contentHash: 0)])
        } else {
            _path = State(initialValue: [])
        }
        #else
        _path = State(initialValue: [])
        #endif
    }

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
            .navigationDestination(for: TmuxSession.self) { session in
                TerminalScreen(session: session, model: model)
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
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                Task { await model.restoreSessions() }
                            } label: {
                                Label("Restore Saved Sessions", systemImage: "arrow.clockwise.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
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
            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
            ForEach(model.sessions) { session in
                NavigationLink(value: session) {
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

    @ViewBuilder
    private var emptyState: some View {
        if let error = model.errorMessage {
            ContentUnavailableView {
                Label("Connection Problem", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await model.refresh() } }
                Button("Settings") { showingSettings = true }
            }
        } else {
            ContentUnavailableView {
                Label("No Sessions", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("No tmux sessions are running on \(model.config.host).")
            } actions: {
                Button("Restore Saved Sessions") { Task { await model.restoreSessions() } }
                    .buttonStyle(.borderedProminent)
                Button("Refresh") { Task { await model.refresh() } }
            }
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
