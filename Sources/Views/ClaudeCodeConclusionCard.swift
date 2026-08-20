import SwiftUI

/// The AI-generated recap of what Claude Code just concluded, shown once
/// after a working → idle transition.
///
/// Deliberately a *separate* card from `ClaudeCodeBanner`, not folded into
/// it: the banner answers "what's happening right now" (a live, ephemeral
/// state); this answers "what did it just say" (a settled fact about the
/// turn that just finished). Merging them would make the banner's meaning
/// ambiguous the moment the two disagree — e.g. summarising is still running
/// while the banner has already flipped to idle.
struct ClaudeCodeConclusionCard: View {
    let summary: ClaudeCodeSummariser.ConclusionSummary?
    let isSummarising: Bool
    let errorMessage: String?

    var body: some View {
        if let summary {
            content(summary)
        } else if isSummarising {
            summarising
        } else if let errorMessage {
            // Silent by default would hide a real signal — Apple Intelligence
            // being off, or the device not supporting it — that's worth
            // surfacing once, unobtrusively, rather than repeating every turn.
            unavailable(errorMessage)
        }
    }

    private func content(_ summary: ClaudeCodeSummariser.ConclusionSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.link)
                Text("SUMMARY")
                    .font(.mono(9.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
            }

            Text(summary.headline)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            if !summary.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(summary.bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .top, spacing: 7) {
                            Text("•")
                                .foregroundStyle(Theme.link)
                            Text(bullet)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 12.5))
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .fill(Theme.link.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .stroke(Theme.link.opacity(0.22), lineWidth: 1)
        )
    }

    private var summarising: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini).tint(Theme.textTertiary)
            Text("Summarising…")
                .font(.mono(11.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    private func unavailable(_ message: String) -> some View {
        Text(message)
            .font(.mono(11))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 13)
            .padding(.vertical, 2)
    }
}
