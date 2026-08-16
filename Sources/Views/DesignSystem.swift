import SwiftUI
import UIKit

/// "Phosphor" — the app's visual identity.
///
/// One dark, terminal-native system across the list, the attach view and the
/// forms. Machine text (session names, pane previews, hosts, times, key caps)
/// is always monospaced; chrome and form labels stay in the system sans.
/// The three accents sit at one lightness/chroma and vary only by hue:
/// green = live, amber = trouble, blue = interactive.
enum Theme {

    // MARK: Palette
    // Authored in oklch, converted to sRGB. Cool near-blacks (hue 250),
    // accents at L 0.78 / C 0.14, hues 155 / 75 / 245.

    /// App background — oklch(0.165 0.010 250)
    static let bgUI = UIColor(red: 0.0435, green: 0.0577, blue: 0.0728, alpha: 1)
    /// Rows, cards, grouped form rows — oklch(0.215 0.012 250)
    static let surfaceUI = UIColor(red: 0.0836, green: 0.1018, blue: 0.1211, alpha: 1)
    /// Key caps and other lifted controls — oklch(0.262 0.013 250)
    static let surfaceRaisedUI = UIColor(red: 0.1248, green: 0.1455, blue: 0.1674, alpha: 1)
    /// Card borders — oklch(0.315 0.012 250)
    static let lineUI = UIColor(red: 0.1768, green: 0.1967, blue: 0.2179, alpha: 1)
    /// Separators — oklch(0.27 0.012 250)
    static let hairlineUI = UIColor(red: 0.1337, green: 0.1529, blue: 0.1733, alpha: 1)
    /// The terminal canvas — deeper than the app background so it reads as a
    /// surface you look *into* — oklch(0.132 0.010 250)
    static let terminalBGUI = UIColor(red: 0.0206, green: 0.0311, blue: 0.0448, alpha: 1)

    static let textUI = UIColor(red: 0.9336, green: 0.9423, blue: 0.9517, alpha: 1)
    static let textSecondaryUI = UIColor(red: 0.6370, green: 0.6532, blue: 0.6707, alpha: 1)
    static let textTertiaryUI = UIColor(red: 0.4398, green: 0.4588, blue: 0.4794, alpha: 1)

    /// Attached / live — phosphor green.
    static let liveUI = UIColor(red: 0.3880, green: 0.8215, blue: 0.5620, alpha: 1)
    /// Dropped / needs attention — amber.
    static let warnUI = UIColor(red: 0.9221, green: 0.6630, blue: 0.2536, alpha: 1)
    /// Interactive / unread — blue.
    static let linkUI = UIColor(red: 0.3813, green: 0.7512, blue: 1.0000, alpha: 1)
    /// Text on a filled `live` button.
    static let onLiveUI = UIColor(red: 0.0254, green: 0.0620, blue: 0.0371, alpha: 1)

    static let bg = Color(uiColor: bgUI)
    static let surface = Color(uiColor: surfaceUI)
    static let surfaceRaised = Color(uiColor: surfaceRaisedUI)
    static let line = Color(uiColor: lineUI)
    static let hairline = Color(uiColor: hairlineUI)
    static let terminalBG = Color(uiColor: terminalBGUI)
    static let text = Color(uiColor: textUI)
    static let textSecondary = Color(uiColor: textSecondaryUI)
    static let textTertiary = Color(uiColor: textTertiaryUI)
    static let live = Color(uiColor: liveUI)
    static let warn = Color(uiColor: warnUI)
    static let link = Color(uiColor: linkUI)
    static let onLive = Color(uiColor: onLiveUI)

    // MARK: Metrics

    enum Radius {
        static let tile: CGFloat = 14
        static let smallTile: CGFloat = 11
        static let card: CGFloat = 18
        static let group: CGFloat = 14
        static let key: CGFloat = 9
        static let button: CGFloat = 12
    }

    /// Leading inset where a session row's text column starts — separators and
    /// the header chip align to it.
    static let rowTextInset: CGFloat = 79
}

// MARK: - Type

extension Font {
    /// Machine text: session names, hosts, previews, key caps, timestamps.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Components

/// A section header in the forms: mono, uppercase, wide-tracked.
struct SectionHeaderText: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.mono(10, .semibold))
            .tracking(1.3)
            .foregroundStyle(Theme.textTertiary)
            .textCase(nil)
    }
}

/// A small round status dot. `live` fills green with a soft halo, `warn` amber,
/// `idle` is a hollow ring.
struct StatusDot: View {
    enum Kind { case live, warn, idle }
    var kind: Kind
    var size: CGFloat = 7

    var body: some View {
        Group {
            switch kind {
            case .live:
                Circle().fill(Theme.live)
                    .overlay(Circle().stroke(Theme.live.opacity(0.22), lineWidth: 3).scaleEffect(1.6))
            case .warn:
                Circle().fill(Theme.warn)
                    .overlay(Circle().stroke(Theme.warn.opacity(0.22), lineWidth: 3).scaleEffect(1.6))
            case .idle:
                Circle().stroke(Theme.textTertiary, lineWidth: 1.4)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The "avatar" for a session or host: a rounded tile carrying the first two
/// characters of the name, tinted green while attached, with a messaging-style
/// presence badge in the corner.
struct SessionTile: View {
    let name: String
    var isAttached: Bool
    var size: CGFloat = 46
    /// Colour the badge is punched out of — the surface behind the tile.
    var punchOut: Color = Theme.bg
    var showsPresence: Bool = true

    /// One letter per segment for multi-part names (`danobat-api` → DA,
    /// `mac-studio` → MS) so sibling hosts like `mac-studio` and `macbook`
    /// don't collapse to the same tile.
    private var initials: String {
        let parts = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if parts.count >= 2 {
            return (parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        guard let first = parts.first else { return "··" }
        return String(first.prefix(2)).uppercased()
    }

    private var radius: CGFloat { size >= 42 ? Theme.Radius.tile : Theme.Radius.smallTile }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(isAttached ? Theme.live.opacity(0.13) : Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(isAttached ? Theme.live.opacity(0.34) : Theme.hairline, lineWidth: 1)
            )
            .overlay(
                Text(initials)
                    .font(.mono(size * 0.32, .semibold))
                    .kerning(-0.3)
                    .foregroundStyle(isAttached ? Theme.live : Theme.textSecondary)
            )
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if showsPresence {
                    Circle()
                        .fill(isAttached ? Theme.live : Theme.line)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(punchOut, lineWidth: 2.5))
                        .offset(x: 2, y: 2)
                }
            }
    }
}

/// The tappable host identity under the list's title — connection state plus
/// `user@host`, and the way into Settings.
struct HostChip: View {
    let label: String
    var isConnected: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(kind: isConnected ? .live : .idle)
            Text(label)
                .font(.mono(11.5, .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    }
}

/// One cap in the terminal's key rail. Caps share the rail width evenly —
/// don't give them differing layout priorities, or the higher-priority caps
/// take the full width and starve the rest to nothing.
struct KeyCap: View {
    let label: String
    /// Spoken label, when the glyph on the cap isn't pronounceable.
    var spoken: String?
    let action: () -> Void

    init(_ label: String, spoken: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.spoken = spoken
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.mono(12, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken ?? label)
    }
}

// MARK: - Modifiers

extension View {
    /// Dark grouped-form treatment shared by Settings, Hosts and the editor.
    func phosphorForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .listRowSeparatorTint(Theme.hairline)
    }

    /// Standard dark navigation bar.
    ///
    /// `opaque` pins the bar's background on, which is what an inline-title
    /// screen wants so its chrome reads as a solid block against the terminal
    /// canvas beneath. Pass `false` on **large-title** screens: forcing
    /// `.visible` there suppresses the large title entirely on iOS 26 — the
    /// title area renders blank. Verified in the simulator; don't re-add it.
    func phosphorNavigationBar(opaque: Bool = true) -> some View {
        self
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbarBackground(opaque ? .visible : .automatic, for: .navigationBar)
    }
}

/// Row-press feedback for list rows that are plain buttons (so they don't get
/// the system disclosure chevron a `NavigationLink` would add).
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Theme.surface : Color.clear)
    }
}
