import AppIntents

/// A saved SSH host, exposed for the (uncommon but supported) case of more
/// than one Mac.
struct SSHHostEntity: AppEntity {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "SSH Host" }
    static var defaultQuery: SSHHostQuery { SSHHostQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SSHHostQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [SSHHostEntity] {
        SettingsStore().loadHosts().map { SSHHostEntity(id: $0.id.uuidString, name: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [SSHHostEntity] {
        let hosts = SettingsStore().loadHosts()
        return identifiers.compactMap { id in
            hosts.first { $0.id.uuidString == id }.map { SSHHostEntity(id: id, name: $0.name) }
        }
    }
}
