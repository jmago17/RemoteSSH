import SwiftUI

/// The app's one rule for adapting to iPad: at *regular* width it shows
/// multi-column chrome (a `NavigationSplitView` with an inline detail pane);
/// at compact width it pushes screens onto a `NavigationStack`.
///
/// Every screen that adapts reads `@Environment(\.horizontalSizeClass)` and
/// asks it `isRegular` — never `UIDevice.userInterfaceIdiom`, so Split View
/// and Slide Over on iPad get the phone layout when they genuinely are
/// phone-width.
extension Optional where Wrapped == UserInterfaceSizeClass {
    var isRegular: Bool { self == .regular }
}

/// Sidebar metrics shared by the session list and Settings, so both columns
/// line up at the same width across the app.
enum SplitMetrics {
    static let sidebarMin: CGFloat = 300
    static let sidebarIdeal: CGFloat = 340
    static let sidebarMax: CGFloat = 420

    /// Settings' category column is narrower — it holds three short labels.
    static let settingsSidebarMin: CGFloat = 240
    static let settingsSidebarIdeal: CGFloat = 268
    static let settingsSidebarMax: CGFloat = 320
}

/// The detail column before anything is picked: a terminal-dark canvas with a
/// prompt-shaped mark, so the empty pane still reads as part of the app rather
/// than dead space.
struct NoSessionSelected: View {
    var isConfigured: Bool

    var body: some View {
        ZStack {
            Theme.terminalBG

            VStack(spacing: 13) {
                Text("$_")
                    .font(.mono(20, .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                            .fill(Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                            .stroke(Theme.line, lineWidth: 1)
                    )

                Text(isConfigured ? "No Session Selected" : "Not Connected")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                // The sidebar already carries the set-up call to action; the
                // detail pane only says what this side of the split is for.
                Text(isConfigured
                     ? "Pick a session on the left to attach — ⌘N starts a new one."
                     : "Set up a connection on the left to list tmux sessions.")
                    .font(.mono(12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }
            .padding(.horizontal, 24)
        }
        .ignoresSafeArea()
    }
}
