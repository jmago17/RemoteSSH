import SwiftUI

/// Connection + credential + poll-interval settings. Single-host for now;
/// multi-host management arrives in a later phase.
struct SettingsView: View {
    @Bindable var model: SessionListModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft = SSHConnectionConfig()
    @State private var secret = ""
    @State private var interval: Double = 5
    @State private var hasExistingSecret = false
    @State private var saveError: String?

    @State private var notificationsEnabled = false
    @State private var ntfyServer = "https://ntfy.sh"
    @State private var ntfyTopic = ""

    private let store = SettingsStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Name") {
                        TextField("Mac", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Host") {
                        TextField("192.168.1.10 or host.local", text: $draft.host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Username") {
                        TextField("user", text: $draft.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Port") {
                        TextField("22", value: $draft.port, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if HostKeyStore.hasTrustedKey(host: draft.host, port: draft.port) {
                        Button("Reset Trusted Host Key", role: .destructive) {
                            HostKeyStore.resetTrust(host: draft.host, port: draft.port)
                        }
                    }
                }

                Section("Authentication") {
                    Picker("Method", selection: $draft.authKind) {
                        ForEach(SSHConnectionConfig.AuthKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }

                    switch draft.authKind {
                    case .password:
                        SecureField(secretPlaceholder, text: $secret)
                    case .privateKey:
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Paste ed25519 private key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $secret)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(minHeight: 120)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            if secret.isEmpty && hasExistingSecret {
                                Text("A key is already stored. Leave blank to keep it.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Polling") {
                    VStack(alignment: .leading) {
                        Text("Refresh every \(Int(interval))s")
                        Slider(value: $interval, in: 2...60, step: 1)
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

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .onAppear {
            draft = model.config
            interval = model.pollInterval
            hasExistingSecret = store.hasStoredSecret(for: draft)
            notificationsEnabled = store.notificationsEnabled
            ntfyServer = store.ntfyServer
            ntfyTopic = store.ntfyTopic
        }
    }

    private var secretPlaceholder: String {
        hasExistingSecret ? "•••••••• (stored — leave blank to keep)" : "Password"
    }

    private func save() {
        do {
            // Persist config first so the secret's Keychain account matches.
            store.saveConfig(draft)
            store.pollInterval = interval

            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                try store.saveSecret(secret, for: draft)
            } else if !hasExistingSecret {
                saveError = "Enter a \(draft.authKind == .password ? "password" : "private key")."
                return
            }

            store.notificationsEnabled = notificationsEnabled
            store.ntfyServer = ntfyServer.trimmingCharacters(in: .whitespaces)
            store.ntfyTopic = ntfyTopic.trimmingCharacters(in: .whitespaces)
            if notificationsEnabled { model.requestNotificationAuthorization() }

            model.reloadConfig()
            dismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
