import SwiftUI

/// A single "conversation" row: an avatar tile with a presence badge, the
/// session name, relative activity time, a one-line pane preview, and an
/// unread dot. Attached-ness is carried entirely by the tile + presence badge,
/// so the name line stays clean.
struct SessionRowView: View {
    let session: TmuxSession

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            SessionTile(name: session.name, isAttached: session.isAttached)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(session.name)
                        .font(.mono(16, .semibold))
                        .kerning(-0.4)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(relativeTime)
                        .font(.mono(11.5, .medium))
                        .foregroundStyle(session.hasUnread ? Theme.link : Theme.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Text(session.preview.isEmpty ? "—" : session.preview)
                    .font(.mono(12.5))
                    .foregroundStyle(session.hasUnread ? Theme.textSecondary : Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.top, 3)

            if session.hasUnread {
                Circle()
                    .fill(Theme.link)
                    .frame(width: 8, height: 8)
                    .padding(.top, 20)
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 20)
        // Inset the separator so it starts where the text column does.
        .alignmentGuide(.listRowSeparatorLeading) { _ in Theme.rowTextInset }
    }

    /// A compact stamp — `now`, `14m`, `3h`, `2d` — so the timestamp stays a
    /// glance-sized column instead of the sentence `.relative` produces.
    /// Refreshes with each poll, which is as current as the row's data.
    private var relativeTime: String {
        let elapsed = Date.now.timeIntervalSince(session.lastActivity)
        switch elapsed {
        case ..<45:
            return "now"
        case ..<3_600:
            return "\(Int(elapsed / 60))m"
        case ..<86_400:
            return "\(Int(elapsed / 3_600))h"
        case ..<(7 * 86_400):
            return "\(Int(elapsed / 86_400))d"
        default:
            return session.lastActivity.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
