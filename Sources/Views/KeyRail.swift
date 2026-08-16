import SwiftUI

// MARK: - Slot configuration

/// The three user-assignable slots on the key rail. `esc` and the expand
/// button are fixed, so these are the only ones the user picks.
enum KeyRailSlot: Int, CaseIterable, Identifiable {
    case one = 1, two = 2, three = 3

    var id: Int { rawValue }
    var storageKey: String { "keyRailSlot\(rawValue)" }

    var `default`: TerminalSession.SpecialKey {
        switch self {
        case .one: return .tab
        case .two: return .shiftTab
        case .three: return .ctrlC
        }
    }

    var spokenPosition: String {
        switch self {
        case .one: return "first"
        case .two: return "second"
        case .three: return "third"
        }
    }
}

/// Reads/writes the three slot assignments. Kept tiny and `UserDefaults`-backed
/// so it works from both the rail and Settings without threading state through.
enum KeyRailConfig {
    static func key(for slot: KeyRailSlot) -> TerminalSession.SpecialKey {
        guard let raw = UserDefaults.standard.string(forKey: slot.storageKey),
              let key = TerminalSession.SpecialKey(rawValue: raw)
        else { return slot.default }
        return key
    }

    static func set(_ key: TerminalSession.SpecialKey, for slot: KeyRailSlot) {
        UserDefaults.standard.set(key.rawValue, forKey: slot.storageKey)
    }

    static func reset() {
        for slot in KeyRailSlot.allCases {
            UserDefaults.standard.removeObject(forKey: slot.storageKey)
        }
    }
}

// MARK: - Expanded key panel

/// The full catalog, shown in place of the software keyboard. Grouped, scrollable,
/// and sized so the terminal above it keeps roughly the same visible rows as it
/// does with the system keyboard up.
struct ExpandedKeyPanel: View {
    let send: (TerminalSession.SpecialKey) -> Void
    let dismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 52, maximum: 84), spacing: 6)]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(TerminalSession.SpecialKey.Group.allCases) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            SectionHeaderText(group.rawValue)
                                .padding(.horizontal, 2)

                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(TerminalSession.SpecialKey.group(group)) { key in
                                    KeyCap(key.label, spoken: key.spoken, stretches: true) {
                                        send(key)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
        }
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    private var header: some View {
        HStack {
            Text("ALL KEYS")
                .font(.mono(9.5, .medium))
                .tracking(0.5)
                .foregroundStyle(Theme.textTertiary)

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.link)
            }
            .accessibilityLabel("Hide all keys")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

// MARK: - Slot picker

/// Assigns one slot. Reachable from a long-press on the cap and from Settings.
struct KeyRailSlotPicker: View {
    let slot: KeyRailSlot
    @Binding var selection: TerminalSession.SpecialKey
    @Environment(\.dismiss) private var dismissSheet

    private let columns = [GridItem(.adaptive(minimum: 60, maximum: 90), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(TerminalSession.SpecialKey.Group.allCases) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeaderText(group.rawValue)

                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(TerminalSession.SpecialKey.group(group)) { key in
                                    Button {
                                        selection = key
                                        KeyRailConfig.set(key, for: slot)
                                        dismissSheet()
                                    } label: {
                                        VStack(spacing: 3) {
                                            Text(key.label)
                                                .font(.mono(14, .semibold))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                            Text(key.spoken)
                                                .font(.system(size: 8.5))
                                                .foregroundStyle(Theme.textTertiary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.7)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(key == selection ? Theme.live.opacity(0.18) : Theme.surfaceRaised)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(key == selection ? Theme.live : Theme.hairline, lineWidth: 1)
                                        )
                                        .foregroundStyle(key == selection ? Theme.live : Theme.text)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Slot \(slot.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .phosphorNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismissSheet() }
                }
            }
        }
    }
}
