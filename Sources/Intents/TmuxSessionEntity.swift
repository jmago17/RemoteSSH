import AppIntents

/// A tmux session, exposed to Siri/Shortcuts as a pickable entity.
///
/// Deliberately thin: an `AppEntity` is a *reference*, not a live model. The
/// session's actual state (attached, preview, Claude Code status) is fetched
/// fresh every time an intent runs — there is no cache to go stale here.
struct TmuxSessionEntity: AppEntity {
    let id: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "tmux Session" }
    static var defaultQuery: TmuxSessionQuery { TmuxSessionQuery() }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

/// Looks sessions up live over SSH. The session count on a personal Mac is
/// small (a handful), so `EnumerableEntityQuery` — the "fetch everything, let
/// Shortcuts filter" shape — is the right fit; a filtering query would be
/// over-engineering for a list this size.
struct TmuxSessionQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [TmuxSessionEntity] {
        let store = SettingsStore()
        let config = store.activeConfig()
        guard config.isComplete, let credential = store.loadCredential(for: config) else {
            // No host configured yet: an empty list reads as "nothing to pick
            // from" in Shortcuts, which is clearer than a thrown error the
            // person can't act on from inside the Shortcuts editor.
            return []
        }
        let sessions = try await TmuxService().fetchSessions(config: config, credential: credential)
        return sessions.map { TmuxSessionEntity(id: $0.name) }
    }

    func entities(for identifiers: [String]) async throws -> [TmuxSessionEntity] {
        // Siri/Shortcuts already knows the identifier (e.g. re-running a
        // saved shortcut) — no need to re-list every session on the Mac to
        // confirm one still exists. If it was killed, sendCommand simply
        // no-ops server-side (tmux's own `|| true`), and the intent reports
        // that back rather than failing this lookup.
        identifiers.map { TmuxSessionEntity(id: $0) }
    }
}
