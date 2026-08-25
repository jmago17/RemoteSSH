import SwiftUI

/// App-wide settings: host management (see `HostListView`), notifications, and
/// polling.
///
/// Same adaptive rule as the session list: one pushed form at compact width, a
/// two-column split (categories → pane) at regular width, where the Hosts list
/// becomes a real detail column instead of a screen you push and pop.
struct SettingsView: View {
    @Bindable var model: SessionListModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var interval: Double = 5
    @State private var notificationsEnabled = false
    @State private var ntfyServer = "https://ntfy.sh"
    @State private var ntfyTopic = ""
    @State private var pane: Pane? = .hosts

    private let store = SettingsStore()

    /// Key-rail slot being reassigned, and a revision counter so the rows
    /// refresh after `UserDefaults` is written behind SwiftUI's back.
    @State private var editingSlot: KeyRailSlot?
    @State private var keyRailRevision = 0

    /// The categories the iPad sidebar lists.
    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case hosts, notifications, polling, keyRail

        var id: Self { self }

        var title: String {
            switch self {
            case .hosts: "Hosts"
            case .notifications: "Notifications"
            case .polling: "Polling"
            case .keyRail: "Key Rail"
            }
        }

        var icon: String {
            switch self {
            case .hosts: "server.rack"
            case .notifications: "bell"
            case .polling: "arrow.clockwise"
            case .keyRail: "keyboard"
            }
        }
    }

    var body: some View {
        Group {
            if horizontalSizeClass.isRegular {
                splitLayout
            } else {
                stackLayout
            }
        }
        .tint(Theme.link)
        .onAppear {
            interval = model.pollInterval
            notificationsEnabled = store.notificationsEnabled
            ntfyServer = store.ntfyServer
            ntfyTopic = store.ntfyTopic
        }
    }

    // MARK: Containers

    private var stackLayout: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        HostListView(model: model)
                    } label: {
                        LabeledContent("Hosts") {
                            Text(activeHostLabel)
                                .font(.mono(13.5))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } header: {
                    SectionHeaderText("Connection")
                }
                .listRowBackground(Theme.surface)

                notificationsSection
                pollingSection
                keyRailSection
            }
            .phosphorForm()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .phosphorNavigationBar()
            .toolbar { doneButton }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label {
                    LabeledContent(pane.title) {
                        Text(summary(for: pane))
                            .font(.mono(12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                } icon: {
                    Image(systemName: pane.icon).foregroundStyle(Theme.link)
                }
                .listRowBackground(Theme.surface)
            }
            .phosphorForm()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .phosphorNavigationBar()
            .navigationSplitViewColumnWidth(
                min: SplitMetrics.settingsSidebarMin,
                ideal: SplitMetrics.settingsSidebarIdeal,
                max: SplitMetrics.settingsSidebarMax
            )
            .toolbar { doneButton }
        } detail: {
            NavigationStack {
                detailPane
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch pane {
        case .hosts, .none:
            HostListView(model: model)
        case .notifications:
            Form { notificationsSection }
                .phosphorForm()
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.inline)
                .phosphorNavigationBar()
        case .polling:
            Form { pollingSection }
                .phosphorForm()
                .navigationTitle("Polling")
                .navigationBarTitleDisplayMode(.inline)
                .phosphorNavigationBar()
        case .keyRail:
            Form { keyRailSection }
                .phosphorForm()
                .navigationTitle("Key Rail")
                .navigationBarTitleDisplayMode(.inline)
                .phosphorNavigationBar()
        }
    }

    @ToolbarContentBuilder
    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { save(); dismiss() }
                .fontWeight(.semibold)
        }
    }

    // MARK: Sections

    /// The three assignable caps on the terminal's key rail. `esc` and the
    /// all-keys button are fixed, so only these three are listed.
    private var keyRailSection: some View {
        Section {
            ForEach(KeyRailSlot.allCases) { slot in
                Button {
                    editingSlot = slot
                } label: {
                    HStack {
                        Text("Slot \(slot.rawValue)")
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(KeyRailConfig.key(for: slot).label)
                            .font(.mono(13, .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            Button("Reset to Defaults") {
                KeyRailConfig.reset()
                keyRailRevision += 1
            }
            .foregroundStyle(Theme.warn)
        } header: {
            SectionHeaderText("Key Rail")
        } footer: {
            Text("esc and the all-keys button are always shown. Long-press a key in the terminal to change it there.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .id(keyRailRevision)
        .sheet(item: $editingSlot) { slot in
            KeyRailSlotPicker(slot: slot, selection: keyRailBinding(slot))
        }
    }

    private func keyRailBinding(_ slot: KeyRailSlot) -> Binding<TerminalSession.SpecialKey> {
        Binding(
            get: { KeyRailConfig.key(for: slot) },
            set: { newValue in
                KeyRailConfig.set(newValue, for: slot)
                keyRailRevision += 1
            }
        )
    }

    private var notificationsSection: some View {
        Section {
            Toggle("Notifications", isOn: $notificationsEnabled)
                .tint(Theme.live)
            if notificationsEnabled {
                LabeledContent("ntfy Server") {
                    TextField("https://ntfy.sh", text: $ntfyServer)
                        .font(.mono(13.5))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Topic") {
                    TextField("your-private-topic", text: $ntfyTopic)
                        .font(.mono(13.5))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            }
            // Push registration, shown rather than hidden. Diagnosing this
            // from the Mac alone is impossible: an absent token file looks the
            // same whether iOS refused to register, or the upload failed, or
            // the app simply hasn't been opened since.
            LabeledContent("Push") {
                Text(APNSRegistration.status.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            SectionHeaderText("Notifications")
        } footer: {
            Text("Get pushed when a session needs attention. Run scripts/tmux-notify.sh on your Mac and subscribe to the same private topic here (and in the ntfy app for background pushes). Pick a hard-to-guess topic — anyone with it can send you notifications.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .listRowBackground(Theme.surface)
    }

    private var pollingSection: some View {
        Section {
            LabeledContent("Refresh") {
                Text("every \(Int(interval))s")
                    .font(.mono(13.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Slider(value: $interval, in: 2...60, step: 1)
                .tint(Theme.live)
        } header: {
            SectionHeaderText("Polling")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: Derived state

    private func summary(for pane: Pane) -> String {
        switch pane {
        case .hosts: activeHostLabel
        case .notifications: notificationsEnabled ? "on" : "off"
        case .polling: "\(Int(interval))s"
        case .keyRail: KeyRailSlot.allCases
            .map { KeyRailConfig.key(for: $0).label }
            .joined(separator: " ")
        }
    }

    private var activeHostLabel: String {
        guard model.config.isComplete else { return "None" }
        return model.config.name.isEmpty ? model.config.host : model.config.name
    }

    private func save() {
        store.pollInterval = interval
        store.notificationsEnabled = notificationsEnabled
        store.ntfyServer = ntfyServer.trimmingCharacters(in: .whitespaces)
        store.ntfyTopic = ntfyTopic.trimmingCharacters(in: .whitespaces)
        if notificationsEnabled { model.requestNotificationAuthorization() }
        model.reloadConfig()
    }
}
