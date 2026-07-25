import Foundation

/// Persists settings. Most settings (hosts, active host, poll interval,
/// notification config) sync across devices via **iCloud Key-Value storage**,
/// mirrored to UserDefaults for offline reads. Secrets live in the Keychain
/// (synced via iCloud Keychain — see KeychainStore). Font size and host-key
/// trust stay device-local.
struct SettingsStore {
    private let defaults: UserDefaults
    private let cloud = NSUbiquitousKeyValueStore.default

    private let configKey = "activeConnectionConfig"   // legacy single-host key
    private let hostsKey = "hosts"
    private let activeHostKey = "activeHostID"
    private let pollKey = "pollIntervalSeconds"
    private let ntfyServerKey = "ntfyServer"
    private let ntfyTopicKey = "ntfyTopic"
    private let notificationsEnabledKey = "notificationsEnabled"

    /// Keys that sync via iCloud (used when mirroring external changes).
    static let syncedKeys = ["hosts", "activeHostID", "pollIntervalSeconds",
                             "ntfyServer", "ntfyTopic", "notificationsEnabled"]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Synced accessors (iCloud KVS, mirrored to UserDefaults)

    private func syncedData(_ key: String) -> Data? {
        cloud.data(forKey: key) ?? defaults.data(forKey: key)
    }
    private func setSynced(_ data: Data?, _ key: String) {
        defaults.set(data, forKey: key)
        if let data { cloud.set(data, forKey: key) } else { cloud.removeObject(forKey: key) }
        cloud.synchronize()
    }
    private func syncedString(_ key: String) -> String? {
        cloud.string(forKey: key) ?? defaults.string(forKey: key)
    }
    private func setSynced(_ string: String?, _ key: String) {
        defaults.set(string, forKey: key)
        if let string { cloud.set(string, forKey: key) } else { cloud.removeObject(forKey: key) }
        cloud.synchronize()
    }

    /// Copies synced keys from iCloud into UserDefaults (call when iCloud reports
    /// an external change, so offline reads stay current).
    func mirrorFromCloud() {
        for key in Self.syncedKeys {
            if let value = cloud.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }

    // MARK: Hosts

    func loadHosts() -> [SSHConnectionConfig] {
        if let data = cloud.data(forKey: hostsKey),
           let hosts = try? JSONDecoder().decode([SSHConnectionConfig].self, from: data) {
            return hosts
        }
        // iCloud empty — seed it from local data (post-upgrade or legacy).
        if let data = defaults.data(forKey: hostsKey),
           let hosts = try? JSONDecoder().decode([SSHConnectionConfig].self, from: data) {
            saveHosts(hosts)
            if cloud.string(forKey: activeHostKey) == nil,
               let local = defaults.string(forKey: activeHostKey) {
                cloud.set(local, forKey: activeHostKey)
            }
            return hosts
        }
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
        setSynced(try? JSONEncoder().encode(hosts), hostsKey)
    }

    var activeHostID: UUID? {
        get { syncedString(activeHostKey).flatMap(UUID.init) }
        nonmutating set { setSynced(newValue?.uuidString, activeHostKey) }
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
            let v = cloud.object(forKey: pollKey) != nil ? cloud.double(forKey: pollKey)
                                                         : defaults.double(forKey: pollKey)
            return v > 0 ? v : 5
        }
        nonmutating set {
            defaults.set(newValue, forKey: pollKey)
            cloud.set(newValue, forKey: pollKey)
            cloud.synchronize()
        }
    }

    // MARK: Notifications (ntfy)

    var ntfyServer: String {
        get {
            let v = syncedString(ntfyServerKey) ?? ""
            return v.isEmpty ? "https://ntfy.sh" : v
        }
        nonmutating set { setSynced(newValue, ntfyServerKey) }
    }

    var ntfyTopic: String {
        get { syncedString(ntfyTopicKey) ?? "" }
        nonmutating set { setSynced(newValue, ntfyTopicKey) }
    }

    var notificationsEnabled: Bool {
        get {
            if cloud.object(forKey: notificationsEnabledKey) != nil {
                return cloud.bool(forKey: notificationsEnabledKey)
            }
            return defaults.bool(forKey: notificationsEnabledKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: notificationsEnabledKey)
            cloud.set(newValue, forKey: notificationsEnabledKey)
            cloud.synchronize()
        }
    }

    // MARK: Secret (Keychain, iCloud-synced)

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
