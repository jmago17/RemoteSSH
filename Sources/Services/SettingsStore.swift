import Foundation

/// Persists the active connection config (UserDefaults) and its secret
/// (Keychain). Keeping the secret out of UserDefaults is deliberate — see
/// the plan's auth requirement that private material never touch disk
/// unencrypted.
struct SettingsStore {
    private let defaults: UserDefaults
    private let configKey = "activeConnectionConfig"
    private let pollKey = "pollIntervalSeconds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Connection config

    func loadConfig() -> SSHConnectionConfig {
        guard let data = defaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(SSHConnectionConfig.self, from: data)
        else { return SSHConnectionConfig() }
        return config
    }

    func saveConfig(_ config: SSHConnectionConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: configKey)
        }
    }

    // MARK: Poll interval

    var pollInterval: TimeInterval {
        get {
            let v = defaults.double(forKey: pollKey)
            return v > 0 ? v : 5
        }
        nonmutating set { defaults.set(newValue, forKey: pollKey) }
    }

    // MARK: Secret (Keychain)

    private func secretAccount(for config: SSHConnectionConfig) -> String {
        "secret-\(config.id.uuidString)"
    }

    func loadCredential(for config: SSHConnectionConfig) -> SSHCredential? {
        guard let secret = KeychainStore.get(secretAccount(for: config)) else { return nil }
        switch config.authKind {
        case .password: return .password(secret)
        case .privateKey: return .privateKey(openSSHText: secret)
        }
    }

    /// Stores the secret string as-is; interpretation is driven by `config.authKind`.
    func saveSecret(_ secret: String, for config: SSHConnectionConfig) throws {
        try KeychainStore.set(secret, for: secretAccount(for: config))
    }

    func hasStoredSecret(for config: SSHConnectionConfig) -> Bool {
        KeychainStore.get(secretAccount(for: config)) != nil
    }
}
