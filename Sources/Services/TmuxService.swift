import Foundation

/// Builds tmux commands and parses their output into `TmuxSession` values.
///
/// Each method owns a full connect → work → disconnect cycle so the
/// non-Sendable `RemoteShell` never escapes a nonisolated async scope. Callers
/// (e.g. the `@MainActor` view model) only ever exchange Sendable values.
struct TmuxService {
    /// Fields, pipe-separated: name | attached | created | activity
    static let listFormat = "#S|#{session_attached}|#{session_created}|#{session_activity}"

    /// Fetches every session plus a short pane preview for each, over a single
    /// SSH connection.
    func fetchSessions(config: SSHConnectionConfig, credential: SSHCredential) async throws -> [TmuxSession] {
        try await withShell(config: config, credential: credential) { shell in
            // `|| true` keeps the exit code zero when tmux has no server
            // running, so we surface "no sessions" rather than an error.
            let raw = try await shell.run(
                "tmux list-sessions -F '\(Self.listFormat)' 2>/dev/null || true"
            )

            var sessions: [TmuxSession] = []
            for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count >= 4 else { continue }

                let name = String(parts[0])
                let attached = parts[1] == "1"
                let created = Date(timeIntervalSince1970: Double(parts[2]) ?? 0)
                let activity = Date(timeIntervalSince1970: Double(parts[3]) ?? 0)

                let pane = (try? await shell.run(
                    "tmux capture-pane -p -t \(Self.quote(name)) -S -3 2>/dev/null || true"
                )) ?? ""

                sessions.append(
                    TmuxSession(
                        name: name,
                        isAttached: attached,
                        created: created,
                        lastActivity: activity,
                        preview: Self.lastNonEmptyLine(pane),
                        contentHash: pane.hashValue
                    )
                )
            }
            // Most recently active first — like a chat list.
            return sessions.sorted { $0.lastActivity > $1.lastActivity }
        }
    }

    /// Full scrollback for the read-only "thread" view (Phase 1).
    func captureScrollback(
        session name: String,
        lines: Int = 2000,
        config: SSHConnectionConfig,
        credential: SSHCredential
    ) async throws -> String {
        try await withShell(config: config, credential: credential) { shell in
            try await shell.run(
                "tmux capture-pane -p -t \(Self.quote(name)) -S -\(lines) 2>/dev/null || true"
            )
        }
    }

    func killSession(_ name: String, config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            _ = try await shell.run("tmux kill-session -t \(Self.quote(name)) 2>/dev/null || true")
        }
    }

    func renameSession(_ name: String, to newName: String, config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            _ = try await shell.run(
                "tmux rename-session -t \(Self.quote(name)) \(Self.quote(newName)) 2>/dev/null || true"
            )
        }
    }

    /// Creates a new detached session. `tmux new-session -d` starts a server if
    /// none is running, so this works from a cold machine too.
    func createSession(_ name: String, config: SSHConnectionConfig, credential: SSHCredential) async throws {
        try await withShell(config: config, credential: credential) { shell in
            _ = try await shell.run("tmux new-session -d -s \(Self.quote(name)) 2>/dev/null || true")
        }
    }

    // MARK: Connection lifecycle

    /// Runs `body` against a connected shell, guaranteeing disconnect. The
    /// `RemoteShell` is created and destroyed entirely within this nonisolated
    /// async scope, so its non-Sendable `SSHClient` never crosses a boundary.
    private func withShell<T: Sendable>(
        config: SSHConnectionConfig,
        credential: SSHCredential,
        _ body: (RemoteShell) async throws -> T
    ) async throws -> T {
        let shell = RemoteShell(config: config, credential: credential)
        do {
            try await shell.connect()
            let result = try await body(shell)
            await shell.disconnect()
            return result
        } catch {
            await shell.disconnect()
            throw error
        }
    }

    // MARK: Parsing helpers

    /// POSIX single-quote escaping so arbitrary session names are shell-safe.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func lastNonEmptyLine(_ text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}
