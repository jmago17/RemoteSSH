import Foundation

/// Persists the active connection config (UserDefaults) and its secret
/// (Keychain). Keeping the secret out of UserDefaults is deliberate — see
/// the plan's auth requirement that private material never touch disk
/// unencrypted.
struct SettingsStore {
    private let defaults: UserDefaults
    private let configKey = "activeConnectionConfig"   // legacy single-host key
    private let hostsKey = "hosts"
    private let activeHostKey = "activeHostID"
    private let pollKey = "pollIntervalSeconds"
    private let ntfyServerKey = "ntfyServer"
    private let ntfyTopicKey = "ntfyTopic"
    private let notificationsEnabledKey = "notificationsEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Hosts

    func loadHosts() -> [SSHConnectionConfig] {
        if let data = defaults.data(forKey: hostsKey),
           let hosts = try? JSONDecoder().decode([SSHConnectionConfig].self, from: data) {
            return hosts
        }
        // Migrate a legacy single-host config into the array.
        if let data = defaults.data(forKey: configKey),
           let legacy = try? JSONDecoder().decode(SSHConnectionConfig.self, from: data) {
            saveHosts([legacy])
            activeHostID = legacy.id
            defaults.removeObject(forKey: configKey)
            return [legacy]
        }
        return []
    }

    func saveHosts(_ hosts: [SSHConnectionConfig]) {
        if let data = try? JSONEncoder().encode(hosts) {
            defaults.set(data, forKey: hostsKey)
        }
    }

    var activeHostID: UUID? {
        get { defaults.string(forKey: activeHostKey).flatMap(UUID.init) }
        nonmutating set { defaults.set(newValue?.uuidString, forKey: activeHostKey) }
    }

    /// The active host, or the first host, or an empty placeholder.
    func activeConfig() -> SSHConnectionConfig {
        let hosts = loadHosts()
        if let id = activeHostID, let host = hosts.first(where: { $0.id == id }) {
            return host
        }
        return hosts.first ?? SSHConnectionConfig()
    }

    /// Inserts or updates a host by id.
    func upsertHost(_ config: SSHConnectionConfig) {
        var hosts = loadHosts()
        if let index = hosts.firstIndex(where: { $0.id == config.id }) {
            hosts[index] = config
        } else {
            hosts.append(config)
        }
        saveHosts(hosts)
        if activeHostID == nil { activeHostID = config.id }
    }

    func deleteHost(_ id: UUID) {
        var hosts = loadHosts()
        hosts.removeAll { $0.id == id }
        saveHosts(hosts)
        try? KeychainStore.remove("secret-\(id.uuidString)")
        if activeHostID == id { activeHostID = hosts.first?.id }
    }

    // MARK: Poll interval

    var pollInterval: TimeInterval {
        get {
            let v = defaults.double(forKey: pollKey)
            return v > 0 ? v : 5
        }
        nonmutating set { defaults.set(newValue, forKey: pollKey) }
    }

    // MARK: Notifications (ntfy)

    var ntfyServer: String {
        get {
            let v = defaults.string(forKey: ntfyServerKey) ?? ""
            return v.isEmpty ? "https://ntfy.sh" : v
        }
        nonmutating set { defaults.set(newValue, forKey: ntfyServerKey) }
    }

    var ntfyTopic: String {
        get { defaults.string(forKey: ntfyTopicKey) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: ntfyTopicKey) }
    }

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: notificationsEnabledKey) }
        nonmutating set { defaults.set(newValue, forKey: notificationsEnabledKey) }
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
