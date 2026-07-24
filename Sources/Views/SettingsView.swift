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
                Section("Connection") {
                    NavigationLink {
                        HostListView(model: model)
                    } label: {
                        LabeledContent("Hosts") {
                            Text(activeHostLabel).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Notifications", isOn: $notificationsEnabled)
                    if notificationsEnabled {
                        LabeledContent("ntfy Server") {
                            TextField("https://ntfy.sh", text: $ntfyServer)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Topic") {
                            TextField("your-private-topic", text: $ntfyTopic)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get pushed when a session needs attention. Run scripts/tmux-notify.sh on your Mac and subscribe to the same private topic here (and in the ntfy app for background pushes). Pick a hard-to-guess topic — anyone with it can send you notifications.")
                }

                Section("Polling") {
                    VStack(alignment: .leading) {
                        Text("Refresh every \(Int(interval))s")
                        Slider(value: $interval, in: 2...60, step: 1)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
        }
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
