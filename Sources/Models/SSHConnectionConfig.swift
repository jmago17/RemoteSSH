import Foundation

/// A saved connection target (one Mac). Multi-host support is planned for a
/// later phase; for now the app persists a single active config.
struct SSHConnectionConfig: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String = "Mac"
    var host: String = ""
    var username: String = ""
    var port: Int = 22

    /// Optional MAC address (e.g. "AA:BB:CC:DD:EE:FF") for Wake-on-LAN when the
    /// Mac is asleep/unreachable. Optional so older saved hosts still decode.
    var macAddress: String?

    var canWakeOnLAN: Bool {
        (macAddress ?? "").split(whereSeparator: { $0 == ":" || $0 == "-" }).count == 6
    }

    /// Which authentication method the stored secret represents.
    var authKind: AuthKind = .password

    var isComplete: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        (1...65535).contains(port)
    }

    enum AuthKind: String, Codable, CaseIterable, Identifiable {
        case password
        case privateKey

        var id: String { rawValue }
        var label: String {
            switch self {
            case .password: return "Password"
            case .privateKey: return "ed25519 Private Key"
            }
        }
    }
}

/// The resolved secret used to authenticate. Never persisted in this struct —
/// it is loaded from the Keychain only at connect time.
enum SSHCredential {
    case password(String)
    /// Raw OpenSSH private-key text (the contents of an `id_ed25519` file).
    case privateKey(openSSHText: String)
}
