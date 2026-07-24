import SwiftUI

/// A single "conversation" row: name, status pill, relative activity time,
/// a one-line pane preview, and an unread dot.
struct SessionRowView: View {
    let session: TmuxSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(session.hasUnread ? Color.accentColor : .clear)
                .frame(width: 9, height: 9)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.headline)
                        .lineLimit(1)
                    statusPill
                    Spacer(minLength: 0)
                    Text(session.lastActivity, format: .relative(presentation: .numeric))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(session.preview.isEmpty ? "—" : session.preview)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusPill: some View {
        Text(session.isAttached ? "attached" : "idle")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(session.isAttached ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
            )
            .foregroundStyle(session.isAttached ? .green : .secondary)
    }
}
