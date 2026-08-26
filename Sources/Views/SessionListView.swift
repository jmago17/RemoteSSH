import SwiftUI

/// The "chat list": one row per tmux session, with the active host's identity
/// sitting under the title as the way into Settings.
///
/// Adaptive shell: at regular width (iPad, and iPad multitasking wide enough
/// to count) the list is the *sidebar* of a `NavigationSplitView` and the
/// terminal lives inline in the detail column; at compact width (iPhone) it
/// stays the `NavigationStack` it has always been and the terminal is pushed.
/// Both paths share one selection — `model.selectedSessionName` — so nothing
/// is lost when the size class flips mid-session.
struct SessionListView: View {
    @Bindable var model: SessionListModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingSettings = false
    @State private var renameTarget: TmuxSession?
    @State private var renameText = ""
    /// The session a kill has been asked for but not yet confirmed. Killing is
    /// not undoable and takes whatever was running inside the session with it,
    /// so both routes to it — the swipe action and the row's context menu —
    /// come through here first.
    @State private var killTarget: TmuxSession?
    @State private var showingNewSession = false
    @State private var newSessionName = ""
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.scenePhase) private var scenePhase

    private var isRegular: Bool { horizontalSizeClass.isRegular }

    var body: some View {
        Group {
            if isRegular {
                splitLayout
            } else {
                stackLayout
            }
        }
        .tint(Theme.link)
        .sheet(isPresented: $showingSettings) {
            if isRegular {
                // A form-sheet is too cramped for Settings' own two columns.
                SettingsView(model: model).presentationSizing(.page)
            } else {
                SettingsView(model: model)
            }
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
        .confirmationDialog(
            killTarget.map { "Kill \($0.name)?" } ?? "Kill session?",
            isPresented: killBinding,
            titleVisibility: .visible,
            presenting: killTarget
        ) { session in
            Button("Kill Session", role: .destructive) {
                Task { await model.kill(session.name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("Whatever is running in \(session.name) is killed with it. tmux can't bring it back.")
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
        .task {
            model.reloadConfig()
            model.startPolling()
        }
        .onChange(of: model.pendingOpenSession) { _, name in
            guard let name else { return }
            model.selectedSessionName = name
            model.pendingOpenSession = nil
        }
        .onDisappear { model.stopPolling() }
        // **This is what stopped the app coming back from the background.**
        //
        // `onDisappear` doesn't fire when the app is merely backgrounded — the
        // view is still "on screen" as far as SwiftUI is concerned — so the
        // poller stayed alive and iOS suspended the process holding an open
        // SSH socket. On return that socket is dead, but the `await` inside
        // the poll loop never learns that and simply never resumes: the task
        // is still non-nil so `startPolling` does nothing, `isRefreshing` is
        // still true, and the only way out is force-quitting the app.
        //
        // Tearing the poller down on the way out and building a fresh one on
        // the way back in fixes it whether or not the stuck task ever notices
        // it was cancelled — the new one doesn't share its socket.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.startPolling()
                model.clearBadge()
            case .background:
                model.stopPolling()
            case .inactive:
                // Transient — the app switcher, a call coming in. The process
                // isn't suspended here, so there's nothing to tear down, and
                // stopping would also fire during the launch transition.
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: Containers

    /// iPhone / compact: today's push navigation, unchanged. The stack path is
    /// derived from the shared selection so there is a single source of truth.
    private var stackLayout: some View {
        NavigationStack(path: stackPath) {
            sidebar
                .navigationDestination(for: String.self) { name in
                    // The conversation is the default way in; the terminal
                    // itself is one tap away from inside it.
                    ChatScreen(sessionName: name, model: model)
                }
        }
    }

    /// iPad / regular: sessions on the left, the attached terminal on the right.
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: SplitMetrics.sidebarMin,
                    ideal: SplitMetrics.sidebarIdeal,
                    max: SplitMetrics.sidebarMax
                )
        } detail: {
            NavigationStack {
                if let name = model.selectedSessionName {
                    // A fresh identity per session so switching rows drops the
                    // old transcript and reads the new session's pane.
                    ChatScreen(sessionName: name, model: model)
                        .id(name)
                } else {
                    NoSessionSelected(isConfigured: model.isConfigured)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The list itself — identical content in both containers.
    private var sidebar: some View {
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
        .navigationTitle("Sessions")
        // A split-view sidebar defaults to an inline title; the phone's large
        // title is the identity, so keep it on both.
        .navigationBarTitleDisplayMode(.large)
        .phosphorNavigationBar(opaque: false)
        .toolbar { listToolbar }
    }

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
        if model.isConfigured {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newSessionName = ""
                    showingNewSession = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Session")
                .keyboardShortcut("n", modifiers: .command)
            }
            // Settings sits on the bar itself rather than behind an overflow
            // menu. What used to be in that menu didn't justify the extra tap
            // it put on the one thing people actually reach for: Refresh
            // duplicated pull-to-refresh, Restore Saved Sessions is already a
            // button on the empty state that prompts it, and the two wake
            // actions belong with the error that makes you want them — see
            // `emptyState`.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        if model.isRefreshing {
            ToolbarItem(placement: .topBarLeading) {
                ProgressView().tint(Theme.textTertiary)
            }
        }
    }

    private var sessionList: some View {
        List {
            Button {
                showingSettings = true
            } label: {
                HostChip(label: hostLabel, isConnected: model.errorMessage == nil)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
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
                    model.selectedSessionName = session.name
                } label: {
                    SessionRowView(session: session)
                }
                .buttonStyle(RowButtonStyle(isSelected: isSelected(session)))
                .hoverEffect(.highlight)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparatorTint(Theme.hairline)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        killTarget = session
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
                // The same two actions on long press. The swipe alone is
                // close to undiscoverable in the split view's sidebar, where
                // the row is narrow and the gesture competes with the
                // column divider.
                .contextMenu {
                    Button {
                        renameTarget = session
                        renameText = session.name
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        killTarget = session
                    } label: {
                        Label("Kill Session", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .refreshable { await model.refresh() }
    }

    /// The banner shown when the connection failed but there are still
    /// sessions on screen from a previous refresh.
    ///
    /// **It carries the same actions as the empty state, deliberately.** Those
    /// used to live only in `emptyState`, which shows when there is nothing to
    /// list — so anyone who had opened the app before saw their old sessions,
    /// this banner saying the Mac might be asleep, and no way to do anything
    /// about it. The list is kept on purpose when the Mac goes away (a sleeping
    /// Mac hasn't lost its sessions), which made that the *common* case rather
    /// than the rare one.
    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

            HStack(spacing: 8) {
                // Same order as the empty state, for the same reason: Wake on
                // LAN is a magic packet and the only one that reaches a
                // sleeping Mac, while Wake Display runs over SSH and needs it
                // already answering.
                if model.config.canWakeOnLAN {
                    bannerButton("Wake Mac", prominent: true) { model.wakeOnLAN() }
                }
                bannerButton("Wake Display") { Task { await model.wakeDisplay() } }
                bannerButton("Retry") { Task { await model.refresh() } }
                Spacer(minLength: 0)
            }
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

    private func bannerButton(
        _ title: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(prominent ? Theme.onLive : Theme.link)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(
                    Capsule().fill(prominent ? Theme.live : Theme.surfaceRaised)
                )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = model.errorMessage {
            ContentUnavailableView {
                Label("Connection Problem", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error).font(.mono(12))
            } actions: {
                // Order matters: Wake on LAN is the only one of the two that
                // can reach a sleeping Mac, since it's a magic packet rather
                // than a command. Wake Display runs `caffeinate` *over SSH*,
                // so it needs the Mac already answering — it's the follow-up
                // once the machine is up, or the fix when the Mac is awake and
                // only its screen is off.
                if model.config.canWakeOnLAN {
                    Button("Wake Mac") { model.wakeOnLAN() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.live)
                        .foregroundStyle(Theme.onLive)
                }
                Button("Wake Display") { Task { await model.wakeDisplay() } }
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

    // MARK: Derived state

    /// Only the split view shows a persistent selection — on the stack the
    /// pushed screen *is* the selection.
    private func isSelected(_ session: TmuxSession) -> Bool {
        isRegular && model.selectedSessionName == session.name
    }

    /// One-deep stack path backed by the shared selection.
    private var stackPath: Binding<[String]> {
        Binding(
            get: { model.selectedSessionName.map { [$0] } ?? [] },
            set: { model.selectedSessionName = $0.last }
        )
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

    private var killBinding: Binding<Bool> {
        Binding(
            get: { killTarget != nil },
            set: { if !$0 { killTarget = nil } }
        )
    }
}
