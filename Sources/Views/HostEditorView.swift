import SwiftUI
import UIKit

/// Add or edit a single host (connection target + credential).
struct HostEditorView: View {
    @Bindable var model: SessionListModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SSHConnectionConfig
    @State private var secret = ""
    @State private var hasExistingSecret: Bool
    @State private var generatedPublicKey: String?
    @State private var saveError: String?

    private let isNew: Bool

    init(model: SessionListModel, host: SSHConnectionConfig?) {
        self.model = model
        let config = host ?? SSHConnectionConfig()
        _draft = State(initialValue: config)
        _hasExistingSecret = State(initialValue: host.map(model.hasSecret(for:)) ?? false)
        isNew = (host == nil)
    }

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
                    LabeledContent("MAC (Wake-on-LAN)") {
                        TextField("optional AA:BB:CC:DD:EE:FF", text: Binding(
                            get: { draft.macAddress ?? "" },
                            set: { draft.macAddress = $0.isEmpty ? nil : $0 }
                        ))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
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
                            Text("Paste an ed25519 private key, or generate one.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $secret)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(minHeight: 100)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            if secret.isEmpty && hasExistingSecret {
                                Text("A key is already stored. Leave blank to keep it.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Generate New Key") { generateKey() }

                        if let publicKey = generatedPublicKey {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Add this public key to ~/.ssh/authorized_keys on your Mac:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(publicKey)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                                Button {
                                    UIPasteboard.general.string = publicKey
                                } label: {
                                    Label("Copy Public Key", systemImage: "doc.on.doc")
                                }
                            }
                        }
                    }
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(isNew ? "Add Host" : "Edit Host")
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
    }

    private var secretPlaceholder: String {
        hasExistingSecret ? "•••••••• (stored — leave blank to keep)" : "Password"
    }

    private func generateKey() {
        let generated = KeyGenerator.generate()
        secret = generated.privateSecret
        generatedPublicKey = generated.publicKeyLine
        draft.authKind = .privateKey
    }

    private func save() {
        guard draft.isComplete else {
            saveError = "Enter a host, username, and valid port."
            return
        }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !hasExistingSecret {
            saveError = "Enter a \(draft.authKind == .password ? "password" : "private key")."
            return
        }
        // Make active when adding a host or editing the one already in use.
        let makeActive = isNew || draft.id == model.config.id
        model.saveHost(draft, secret: trimmed.isEmpty ? nil : secret, makeActive: makeActive)
        dismiss()
    }
}
