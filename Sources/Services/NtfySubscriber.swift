import Foundation

/// Subscribes to an ntfy topic's JSON stream while the app is in the
/// foreground, invoking `onMessage(session, body)` for each published message.
///
/// This is the foreground path; true background delivery (app suspended/killed)
/// needs APNs, which ntfy's own app already provides — subscribe to the same
/// topic there for backgrounded pushes. See scripts/tmux-notify.sh.
actor NtfySubscriber {
    private var task: Task<Void, Never>?

    func start(server: String, topic: String, onMessage: @escaping @Sendable (String, String) -> Void) {
        stop()
        let base = server.hasSuffix("/") ? String(server.dropLast()) : server
        guard let url = URL(string: "\(base)/\(topic)/json") else { return }
        task = Task { await Self.stream(url: url, onMessage: onMessage) }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Reconnecting read loop over the ntfy JSON stream. Standalone (only
    /// Sendable inputs) so it stays in a single task isolation region.
    private static func stream(url: URL, onMessage: @escaping @Sendable (String, String) -> Void) async {
        while !Task.isCancelled {
            do {
                let (bytes, _) = try await URLSession.shared.bytes(from: url)
                for try await line in bytes.lines {
                    if Task.isCancelled { return }
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          obj["event"] as? String == "message"
                    else { continue }

                    let title = obj["title"] as? String
                    let message = obj["message"] as? String ?? ""
                    let session = session(fromClick: obj["click"] as? String)
                        ?? title.map(stripSuffix) ?? "tmux"
                    onMessage(session, message)
                }
            } catch {
                // Network error / stream closed — fall through to reconnect.
            }
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(5)) // backoff before reconnect
        }
    }

    /// Parses the session name from a `remotessh://open/<name>` click URL.
    static func session(fromClick click: String?) -> String? {
        let prefix = "remotessh://open/"
        guard let click, click.hasPrefix(prefix) else { return nil }
        return String(click.dropFirst(prefix.count)).removingPercentEncoding
    }

    /// The watcher titles messages "<session> needs attention"; recover the name.
    private static func stripSuffix(_ title: String) -> String {
        title.replacingOccurrences(of: " needs attention", with: "")
    }
}
