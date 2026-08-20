import SwiftUI

/// One turn in the conversation.
///
/// The whole readability of this view rests on one contrast: a *command* is a
/// chat bubble — right-aligned, blue-tinted, intrinsically sized — while
/// *output* stays a terminal block: full width, on the deeper terminal canvas,
/// and always monospaced with its whitespace intact. Shell output is not prose
/// and must never be reflowed into it; column alignment in `ls -l`, `git status`
/// or a build log is information.
struct TranscriptTurnView: View {
    let turn: TranscriptTurn
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    /// Lines shown before an output block is collapsed. A 5000-line build log
    /// would otherwise make the whole transcript unusable.
    private static let collapsedLineLimit = 24

    var body: some View {
        switch turn.kind {
        case .command: commandBubble
        case .output: outputBlock(isRaw: false)
        case .raw: outputBlock(isRaw: true)
        }
    }

    // MARK: What I typed

    private var commandBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            bubble
            // Shown here rather than on the output block because a failing
            // command often prints nothing at all — `false`, a bad `cd`.
            if let code = turn.exitCode, code != 0 {
                TurnTag(text: "exit \(code)", tint: Theme.warn)
                    .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var bubble: some View {
        HStack {
            Spacer(minLength: 40)
            HStack(alignment: .top, spacing: 8) {
                Text("$")
                    .font(.mono(13, .medium))
                    .foregroundStyle(Theme.link)
                Text(turn.text)
                    .font(.mono(13, .medium))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 15,
                    bottomLeadingRadius: 15,
                    bottomTrailingRadius: 5,
                    topTrailingRadius: 15,
                    style: .continuous
                )
                .fill(Theme.link.opacity(0.14))
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 15,
                    bottomLeadingRadius: 15,
                    bottomTrailingRadius: 5,
                    topTrailingRadius: 15,
                    style: .continuous
                )
                .stroke(Theme.link.opacity(0.34), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You ran: \(turn.text)")
    }

    // MARK: What the machine answered

    private func outputBlock(isRaw: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isRaw || turn.isLikelyError || turn.exitCode != nil {
                HStack(spacing: 7) {
                    if isRaw {
                        TurnTag(text: "raw pane", tint: Theme.warn)
                    } else if let code = turn.exitCode, code != 0 {
                        TurnTag(text: "exit \(code)", tint: Theme.warn)
                    } else if turn.isLikelyError {
                        TurnTag(text: "looks like an error", tint: Theme.warn)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 0) {
                // Horizontal scrolling rather than wrapping: a wrapped build log
                // or `ls -l` loses the column structure that makes it readable.
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(visibleText)
                        .font(.mono(12.5))
                        .foregroundStyle(Theme.text.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, isTruncated ? 8 : 10)
                }

                if isTruncated || isExpanded {
                    expandFooter
                }
            }
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 15,
                    bottomLeadingRadius: 5,
                    bottomTrailingRadius: 15,
                    topTrailingRadius: 15,
                    style: .continuous
                )
                .fill(Theme.terminalBG)
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 15,
                    bottomLeadingRadius: 5,
                    bottomTrailingRadius: 15,
                    topTrailingRadius: 15,
                    style: .continuous
                )
                .stroke(borderColour, lineWidth: 1)
            )
        }
    }

    private var expandFooter: some View {
        Button(action: onToggleExpanded) {
            HStack {
                Text(isExpanded
                     ? "\(turn.lineCount) lines"
                     : "\(turn.lineCount - Self.collapsedLineLimit) more lines")
                    .font(.mono(11, .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(isExpanded ? "Show less" : "Show all")
                    .font(.mono(11, .medium))
                    .foregroundStyle(Theme.link)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    // MARK: Derived

    private var isTruncated: Bool {
        !isExpanded && turn.lineCount > Self.collapsedLineLimit
    }

    private var visibleText: String {
        guard isTruncated else { return turn.text }
        return turn.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(Self.collapsedLineLimit)
            .joined(separator: "\n")
    }

    private var borderColour: Color {
        if turn.kind == .raw { return Theme.warn.opacity(0.30) }
        if turn.exitCode.map({ $0 != 0 }) ?? turn.isLikelyError { return Theme.warn.opacity(0.38) }
        return Theme.hairline
    }
}

/// A small uppercase chip above an output block — `exit 65`, `raw pane`.
struct TurnTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.mono(9, .semibold))
            .tracking(0.7)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.opacity(0.16)))
    }
}

/// Explains, in plain words, why the transcript isn't a conversation.
///
/// This exists because the alternative — silently showing a dump — reads as a
/// bug. Saying "this is a full-screen program, open the terminal" turns a
/// parser limitation into a useful signpost.
struct FallbackNote: View {
    let fallback: Transcript.Fallback
    let onOpenTerminal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.warn)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(fallback.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpenTerminal) {
                    Text("Open the terminal")
                        .font(.mono(11.5, .medium))
                        .foregroundStyle(Theme.link)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .fill(Theme.warn.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .stroke(Theme.warn.opacity(0.26), lineWidth: 1)
        )
    }
}

/// The command the user just sent, shown while the pane catches up so the
/// composer doesn't appear to swallow it.
struct PendingCommandBubble: View {
    let command: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            HStack(alignment: .top, spacing: 8) {
                Text("$")
                    .font(.mono(13, .medium))
                    .foregroundStyle(Theme.link.opacity(0.6))
                Text(command)
                    .font(.mono(13, .medium))
                    .foregroundStyle(Theme.textSecondary)
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 15,
                    bottomLeadingRadius: 15,
                    bottomTrailingRadius: 5,
                    topTrailingRadius: 15,
                    style: .continuous
                )
                .fill(Theme.link.opacity(0.07))
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 15,
                    bottomLeadingRadius: 15,
                    bottomTrailingRadius: 5,
                    topTrailingRadius: 15,
                    style: .continuous
                )
                .stroke(Theme.link.opacity(0.18), lineWidth: 1)
            )
        }
    }
}
