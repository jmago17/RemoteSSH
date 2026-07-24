import Foundation

/// One tmux session, presented as a "conversation" in the list.
struct TmuxSession: Identifiable, Hashable {
    /// tmux session names are unique per server, so they double as the id.
    var id: String { name }

    let name: String
    let isAttached: Bool
    let created: Date
    let lastActivity: Date

    /// Last non-empty line of the pane — the "last message" preview.
    var preview: String

    /// A stable hash of the current pane snapshot, used for unread detection.
    var contentHash: Int

    /// True when the pane changed since the user last opened this session.
    var hasUnread: Bool = false
}
