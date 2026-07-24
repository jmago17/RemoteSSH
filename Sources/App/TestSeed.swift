#if DEBUG
import Foundation

/// DEBUG-only helper to configure the app from launch environment, so the
/// connection can be exercised in the simulator without driving the Settings
/// UI. Never compiled into Release builds.
///
/// Trigger by launching with the `--seed-test-config` argument and these
/// environment variables (via `simctl`'s `SIMCTL_CHILD_*` prefix):
///   REMOTESSH_HOST, REMOTESSH_USER, REMOTESSH_PORT,
///   REMOTESSH_KEY (ed25519 private-key text) or REMOTESSH_PASSWORD
enum TestSeed {
    static func applyIfRequested() {
        let info = ProcessInfo.processInfo
        guard info.arguments.contains("--seed-test-config") else { return }

        let env = info.environment
        guard let host = env["REMOTESSH_HOST"], let user = env["REMOTESSH_USER"] else { return }

        var config = SSHConnectionConfig()
        config.name = "Localhost"
        config.host = host
        config.username = user
        config.port = Int(env["REMOTESSH_PORT"] ?? "22") ?? 22

        let store = SettingsStore()
        if let key = env["REMOTESSH_KEY"], !key.isEmpty {
            config.authKind = .privateKey
            store.saveConfig(config)
            try? store.saveSecret(key, for: config)
        } else if let password = env["REMOTESSH_PASSWORD"], !password.isEmpty {
            config.authKind = .password
            store.saveConfig(config)
            try? store.saveSecret(password, for: config)
        }
    }
}
#endif
