import SwiftUI

/// App-wide settings: host management (see `HostListView`), notifications, and
/// polling.
struct SettingsView: View {
    @Bindable var model: SessionListModel
    @Environment(\.dismiss) private var dismiss

    @State private var interval: Double = 5
    @State private var notificationsEnabled = false
    @State private var ntfyServer = "https://ntfy.sh"
    @State private var ntfyTopic = ""

    private let store = SettingsStore()

    var body: some View {
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
                } header: {
                    SectionHeaderText("Notifications")
                } footer: {
                    Text("Get pushed when a session needs attention. Run scripts/tmux-notify.sh on your Mac and subscribe to the same private topic here (and in the ntfy app for background pushes). Pick a hard-to-guess topic — anyone with it can send you notifications.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

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
            .phosphorForm()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .phosphorNavigationBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                        .fontWeight(.semibold)
                }
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
