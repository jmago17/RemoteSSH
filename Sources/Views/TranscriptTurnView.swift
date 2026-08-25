import SwiftUI
import UIKit

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
    /// Width of the transcript column, measured once by `ChatScreen`. Zero
    /// until the first layout pass, which simply means "don't shrink anything
    /// yet".
    let availableWidth: CGFloat
    /// The pane's real column count, when tmux told us. See `fittingColumns`.
    var paneColumns: Int = 0
    let onToggleExpanded: () -> Void

    /// Lines shown before an output block is collapsed. A 5000-line build log
    /// would otherwise make the whole transcript unusable.
    private static let collapsedLineLimit = 24

    /// Type size for output when it already fits.
    private static let baseOutputFontSize: CGFloat = 12.5

    /// The floor for shrink-to-fit. Below this the block goes back to
    /// scrolling sideways instead: a 200-column build log would otherwise be
    /// rendered at about 4pt, which fits and is unreadable, which is worse
    /// than not fitting.
    ///
    /// 7.5 rather than a rounder 8 or 9 because the floor has to clear the
    /// case this feature exists for. Measured: a Claude Code pane is 61
    /// columns, an iPhone 17 Pro gives the transcript 374pt, a block spends 24
    /// of them on padding — so the widest real line needs 9.6pt and fits
    /// comfortably. The floor's job is the *next* case down: an 80-column
    /// shell pane needs 7.3pt, close enough that 7.5 keeps all but the last
    /// character or two on screen, where 8.5 would have cut a whole word off
    /// every line.
    private static let minimumOutputFontSize: CGFloat = 7.5

    /// Horizontal padding inside an output block, both sides together.
    private static let blockPadding: CGFloat = 24

    /// Advance width of one monospaced character per point of type size.
    /// Measured from the real font rather than assumed: `.system(design:
    /// .monospaced)` resolves to SF Mono, whose advance happens to be ~0.6em,
    /// but that is a fact about today's font, not a promise of the API.
    private static let advanceRatio: CGFloat = {
        let probe = UIFont.monospacedSystemFont(ofSize: 100, weight: .regular)
        return "0".size(withAttributes: [.font: probe]).width / 100
    }()

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
                //
                // The `maxWidth: .infinity` belongs on the ScrollView, not on
                // the Text inside it. Putting it on the Text — as this used to
                // do — proposes an unbounded width to something already inside
                // an unbounded scroll axis, and iPhone vs iPad resolve that
                // ambiguity in opposite directions: the block either overflows
                // past the screen edge (iPhone, nothing visible) or collapses
                // to its content width and leaves a gap (iPad). `fixedSize`
                // gives the text its true intrinsic width so the scroll view
                // has something concrete to scroll, and the outer frame is
                // what actually claims the available column width.
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(renderedText)
                        .font(.mono(outputFontSize))
                        .foregroundStyle(Theme.text.opacity(0.92))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, isTruncated ? 8 : 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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

    // MARK: Fitting output to the screen

    /// How many columns this block genuinely needs.
    ///
    /// Decorative rules are excluded deliberately. `capture-pane -S -2000`
    /// reaches back into scrollback written when the pane had a *different*
    /// width, so a Claude Code session that is 61 columns wide today still
    /// carries `────…` lines 240 characters long from when the window was
    /// wide. Sizing to those would shrink every real line to a quarter of what
    /// it needs, and they are the reason the horizontal scroll used to run
    /// four times longer than any readable text — most of the drag travelled
    /// along a ruler.
    private var contentColumns: Int {
        visibleText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .lazy
            .filter { !Self.isDecorativeRule($0) }
            .map(\.count)
            .max() ?? 0
    }

    /// A line that is nothing but box-drawing or separator glyphs. The length
    /// floor keeps a genuine `--` or a `│` gutter character from qualifying.
    private static func isDecorativeRule(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 8 else { return false }
        return trimmed.allSatisfy { "─━═-–—_·⎯│┌┐└┘├┤┬┴┼╌╍┄┅".contains($0) }
    }

    /// Shrinks the type just enough for the widest real line to fit, the way a
    /// terminal app fits columns to the screen.
    ///
    /// No amount of `frame` or `fixedSize` work can fix this case, which is
    /// why the previous attempt didn't: a 61-column pane at 12.5pt needs about
    /// 460pt and an iPhone offers about 360pt. The last columns were simply
    /// off-screen, and the only way to see them was to notice the block
    /// scrolled sideways at all.
    /// The column count to size the type to.
    ///
    /// **The pane's own width, not the longest line in the block.** Sizing to
    /// the content looks right in a screenshot and is unusable in motion: the
    /// widest line changes every time the agent prints something, so the font
    /// size changes with it and the whole block visibly re-flows on every
    /// refresh. Coming back from the terminal looked fine precisely because
    /// the size had just been recomputed — the next line of output undid it.
    ///
    /// The pane's width is the stable answer, and it's the same rule a
    /// terminal follows: fit the columns the session actually has. Scrollback
    /// written when the pane was wider still overflows into the horizontal
    /// scroll, which is what a terminal does too.
    ///
    /// Falls back to the content when tmux didn't say (an older snapshot, a
    /// transcript built from plain text).
    /// How many columns this screen can show at a size that is still readable.
    ///
    /// Deliberately not the *smallest* readable size: asking tmux for 77
    /// columns because they technically fit at the 7.5pt floor would trade the
    /// scroll bar for a squint. `readableFontSize` is the size the transcript
    /// wants to render at, so this is the width that gets it.
    static func columnsThatFit(width: CGFloat) -> Int {
        let usable = width - blockPadding
        guard usable > 0 else { return 0 }
        return Int(usable / (readableFontSize * advanceRatio))
    }

    /// The size the fitted text should end up at — comfortably above the
    /// shrink-to-fit floor.
    static let readableFontSize: CGFloat = 9.5

    private var fittingColumns: Int {
        paneColumns > 0 ? paneColumns : contentColumns
    }

    private var outputFontSize: CGFloat {
        let columns = fittingColumns
        guard columns > 0, availableWidth > 0 else { return Self.baseOutputFontSize }
        let usable = availableWidth - Self.blockPadding
        guard usable > 0 else { return Self.baseOutputFontSize }
        let fitted = usable / (CGFloat(columns) * Self.advanceRatio)
        return min(Self.baseOutputFontSize, max(Self.minimumOutputFontSize, fitted))
    }

    /// The text as drawn: `visibleText` with decorative rules clipped to the
    /// block's own width. Clipping ornament is safe in a way that clipping
    /// content never is, and it stops one stale 240-character rule from
    /// dictating the width of a scroll canvas nobody wants to drag across.
    private var renderedText: String {
        let columns = contentColumns
        guard columns > 0 else { return visibleText }
        return visibleText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                Self.isDecorativeRule(line) && line.count > columns
                    ? line.prefix(columns)
                    : line
            }
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
