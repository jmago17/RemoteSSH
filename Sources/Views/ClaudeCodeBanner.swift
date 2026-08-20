import SwiftUI

/// A live status banner for a pane running Claude Code.
///
/// The deliberate scope: this reports **state**, not content. It answers the
/// question you actually have when you pull the phone out — *is it working, is
/// it done, does it need me?* — and leaves Claude Code's own frame to render
/// itself underneath, verbatim.
struct ClaudeCodeBanner: View {
    let status: ClaudeCodeStatus
    var onOpenTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                icon
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 6)
                if status.needsAttention {
                    Button(action: onOpenTerminal) {
                        Text("Answer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.onLive)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.live))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let task = status.task {
                Text(task)
                    .font(.mono(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !metrics.isEmpty {
                Text(metrics)
                    .font(.mono(11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .fill(accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .stroke(accent.opacity(0.30), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var icon: some View {
        switch status.activity {
        case .working:
            PulsingDot(color: accent)
        case .awaitingApproval:
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(accent)
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(accent)
        }
    }

    private var headline: String {
        switch status.activity {
        case .working(let verb): return "Claude Code · \(verb)"
        case .awaitingApproval: return "Claude Code is waiting for you"
        case .idle: return "Claude Code · idle"
        }
    }

    /// Elapsed and tokens, whichever were present.
    private var metrics: String {
        var parts: [String] = []
        if let e = status.elapsed { parts.append(e) }
        if let t = status.tokens { parts.append("↓ \(t) tokens") }
        if let d = status.detail { parts.append(d) }
        return parts.joined(separator: "  ·  ")
    }

    private var accent: Color {
        switch status.activity {
        case .working: return Theme.link
        case .awaitingApproval: return Theme.warn
        case .idle: return Theme.live
        }
    }
}

/// A soft breathing dot — the pane is alive and the number on screen is moving.
private struct PulsingDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(on ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
