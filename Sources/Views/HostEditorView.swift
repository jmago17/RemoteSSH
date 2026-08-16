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
                Section {
                    field("Name") {
                        TextField("Mac", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                    }
                    field("Host") {
                        TextField("192.168.1.10 or host.local", text: $draft.host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .multilineTextAlignment(.trailing)
                    }
                    field("Username") {
                        TextField("user", text: $draft.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    field("Port") {
                        TextField("22", value: $draft.port, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    field("Wake-on-LAN") {
                        TextField("AA:BB:CC:DD:EE:FF", text: Binding(
                            get: { draft.macAddress ?? "" },
                            set: { draft.macAddress = $0.isEmpty ? nil : $0 }
                        ))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                    }
                } header: {
                    SectionHeaderText("Connection")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker("Method", selection: $draft.authKind) {
                        ForEach(SSHConnectionConfig.AuthKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 6, trailing: 14))

                    switch draft.authKind {
                    case .password:
                        SecureField(secretPlaceholder, text: $secret)
                            .font(.mono(13.5))
                    case .privateKey:
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Paste an ed25519 private key, or generate one.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                            TextEditor(text: $secret)
                                .font(.mono(10.5))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 100)
                                .padding(9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Theme.terminalBG)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Theme.hairline, lineWidth: 1)
                                )
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            if secret.isEmpty && hasExistingSecret {
                                Text("A key is already stored. Leave blank to keep it.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .padding(.vertical, 2)

                        Button("Generate New ed25519 Key") { generateKey() }
                            .foregroundStyle(Theme.link)

                        if let publicKey = generatedPublicKey {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Add this public key to ~/.ssh/authorized_keys on your Mac:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                                Text(publicKey)
                                    .font(.mono(10))
                                    .foregroundStyle(Theme.textSecondary)
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                                Button {
                                    UIPasteboard.general.string = publicKey
                                } label: {
                                    Label("Copy Public Key", systemImage: "doc.on.doc")
                                        .font(.system(size: 13))
                                }
                                .foregroundStyle(Theme.link)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    SectionHeaderText("Authentication")
                } footer: {
                    Text("Stored in the iOS Keychain, synced via iCloud — never on disk.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                if HostKeyStore.hasTrustedKey(host: draft.host, port: draft.port) {
                    Section {
                        Button("Reset Trusted Host Key") {
                            HostKeyStore.resetTrust(host: draft.host, port: draft.port)
                        }
                        .foregroundStyle(Theme.warn)
                    }
                    .listRowBackground(Theme.surface)
                }

                if let saveError {
                    Section {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.warn)
                                .padding(.top, 1)
                            Text(saveError)
                                .font(.mono(11.5))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .listRowBackground(Theme.warn.opacity(0.10))
                }
            }
            .phosphorForm()
            .navigationTitle(isNew ? "Add Host" : "Edit Host")
            .navigationBarTitleDisplayMode(.inline)
            .phosphorNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.link)
    }

    /// A label / mono-value row, so typed connection details read as machine
    /// text against sans labels.
    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LabeledContent(label) {
            content()
                .font(.mono(13.5))
                .foregroundStyle(Theme.textSecondary)
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
