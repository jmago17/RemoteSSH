import SwiftUI

/// A session's "thread": a full interactive SwiftTerm terminal bound to
/// `tmux attach -t <name>` over a live SSH PTY.
///
/// The chrome around it does the work the old flat-black screen didn't: a
/// title block naming the session and its host, a status rail that reads
/// live / attaching / dropped at a glance, and a key rail for the keys the
/// soft keyboard can't produce.
struct TerminalScreen: View {
    /// Identified by name, not by value: the poll replaces every `TmuxSession`
    /// a few seconds later, and the split view's selection has to outlive that.
    let sessionName: String
    @Bindable var model: SessionListModel

    @State private var terminal: TerminalSession?
    @State private var setupError: String?
    @State private var generation = 0
    @AppStorage("terminalFontSize") private var fontSize: Double = 13
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// At iPad width the pane is the detail column, not a pushed screen: the
    /// canvas gets room to breathe and "back" means clearing the selection.
    private var isRegular: Bool { horizontalSizeClass.isRegular }

    /// Which slot the long-press picker is editing, if any.
    @State private var editingSlot: KeyRailSlot?
    /// When true the expanded key panel replaces the software keyboard.
    @State private var showAllKeys = false
    /// Slot assignments, mirrored so the rail redraws when the picker writes.
    @AppStorage(KeyRailSlot.one.storageKey) private var slot1Raw = KeyRailSlot.one.default.rawValue
    @AppStorage(KeyRailSlot.two.storageKey) private var slot2Raw = KeyRailSlot.two.default.rawValue
    @AppStorage(KeyRailSlot.three.storageKey) private var slot3Raw = KeyRailSlot.three.default.rawValue
    @FocusState private var keyboardHidden: Bool

    /// Roughly a software-keyboard's worth of height, so the visible terminal
    /// rows don't jump when swapping one for the other.
    private var expandedPanelHeight: CGFloat { isRegular ? 300 : 260 }

    private func slotKey(_ slot: KeyRailSlot) -> TerminalSession.SpecialKey {
        let raw: String
        switch slot {
        case .one: raw = slot1Raw
        case .two: raw = slot2Raw
        case .three: raw = slot3Raw
        }
        return TerminalSession.SpecialKey(rawValue: raw) ?? slot.default
    }

    private func slotBinding(_ slot: KeyRailSlot) -> Binding<TerminalSession.SpecialKey> {
        Binding(
            get: { slotKey(slot) },
            set: { newValue in
                switch slot {
                case .one: slot1Raw = newValue.rawValue
                case .two: slot2Raw = newValue.rawValue
                case .three: slot3Raw = newValue.rawValue
                }
            }
        )
    }

    /// Swaps the software keyboard for the full key catalog (and back). The
    /// terminal keeps first responder either way, so typed input still lands.
    private func toggleAllKeys() {
        withAnimation(.snappy(duration: 0.22)) {
            showAllKeys.toggle()
        }
        if showAllKeys {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusRail(phase: terminal?.phase, hasSetupError: setupError != nil)

            ZStack {
                Theme.terminalBG

                if let terminal {
                    // A new id on reconnect forces a fresh SwiftTerm view + attach.
                    TerminalHostView(session: terminal, fontSize: CGFloat(fontSize))
                        .id(generation)
                        .padding(.horizontal, isRegular ? 14 : 6)
                        .padding(.top, isRegular ? 10 : 6)
                        .opacity(isConnecting(terminal) ? 0 : 1)

                    statusOverlay(terminal)
                } else if let setupError {
                    attachFailed(setupError)
                } else {
                    connectingOverlay(command: "tmux attach -t \(sessionName)")
                }
            }

            keyRail

            if showAllKeys {
                ExpandedKeyPanel(
                    send: { terminal?.sendKey($0) },
                    dismiss: { withAnimation(.snappy(duration: 0.22)) { showAllKeys = false } }
                )
                .frame(height: expandedPanelHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $editingSlot) { slot in
            KeyRailSlotPicker(slot: slot, selection: slotBinding(slot))
        }
        .background(Theme.terminalBG)
        .navigationTitle(sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .phosphorNavigationBar()
        .toolbar {
            ToolbarItem(placement: .principal) { titleBlock }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Text Size") {
                        Button {
                            fontSize = min(fontSize + 1, 28)
                        } label: { Label("Bigger", systemImage: "textformat.size.larger") }
                        Button {
                            fontSize = max(fontSize - 1, 8)
                        } label: { Label("Smaller", systemImage: "textformat.size.smaller") }
                    }
                    Section {
                        Button {
                            reconnect()
                        } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Terminal Options")
            }
        }
        .onAppear {
            model.markRead(sessionName)
            setup()
        }
        .onDisappear { terminal?.stop() }
        .onChange(of: scenePhase) { _, phase in
            // iOS suspends the socket in the background; re-attach on return so
            // the pane catches up near-seamlessly.
            if phase == .active, case .closed = terminal?.phase { reconnect() }
        }
    }

    // MARK: Chrome

    /// The inline title: session name over its host and live geometry.
    private var titleBlock: some View {
        VStack(spacing: 1) {
            Text(sessionName)
                .font(.mono(15, .semibold))
                .kerning(-0.3)
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            HStack(spacing: 5) {
                StatusDot(kind: statusDotKind, size: 6)
                Text(statusLabel.uppercased())
                    .font(.mono(9.5, .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The keys the soft keyboard can't produce, surfaced instead of buried in
    /// a menu. On the phone the caps share the rail evenly; at iPad width
    /// stretching five caps across 900pt would read as a toolbar of slabs, so
    /// they keep their intrinsic width and sit leading.
    private var keyRail: some View {
        HStack(spacing: isRegular ? 7 : 6) {
            // Fixed: escape earns its slot in every terminal.
            KeyCap("esc", spoken: "Escape", stretches: !isRegular) { terminal?.sendKey(.escape) }

            // Three user-assignable slots. Long-press a cap to reassign it.
            ForEach(KeyRailSlot.allCases) { slot in
                let key = slotKey(slot)
                KeyCap(key.label, spoken: key.spoken, stretches: !isRegular) {
                    terminal?.sendKey(key)
                }
                .contextMenu {
                    Button {
                        editingSlot = slot
                    } label: {
                        Label("Change \(slot.spokenPosition) key", systemImage: "square.grid.2x2")
                    }
                }
            }

            // Fixed: everything else lives behind this, in place of the keyboard.
            KeyCap(symbol: showAllKeys ? "chevron.down" : "square.grid.2x2",
                   spoken: showAllKeys ? "Hide all keys" : "Show all keys",
                   stretches: !isRegular) {
                toggleAllKeys()
            }

            if isRegular { Spacer(minLength: 0) }
        }
        .padding(.horizontal, isRegular ? 14 : 12)
        .padding(.vertical, 9)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .disabled(terminal == nil || !isLive)
        .opacity(isLive ? 1 : 0.4)
    }

    // MARK: States

    @ViewBuilder
    private func statusOverlay(_ terminal: TerminalSession) -> some View {
        switch terminal.phase {
        case .connecting:
            connectingOverlay(command: "tmux attach -t \(sessionName)")
        case .closed(let message):
            endedOverlay(message)
        case .live:
            EmptyView()
        }
    }

    /// Attaching: a terminal-native pulse over the canvas, naming the exact
    /// command and the host it's running on.
    private func connectingOverlay(command: String) -> some View {
        ZStack {
            Theme.terminalBG
            VStack(spacing: 14) {
                PulsingDots()
                Text(command)
                    .font(.mono(13, .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(model.config.username)@\(model.config.host):\(model.config.port)")
                    .font(.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    /// Dropped or detached: the scrollback stays faintly visible behind a card
    /// that says what happened and offers the way back in.
    private func endedOverlay(_ message: String?) -> some View {
        ZStack {
            Theme.terminalBG.opacity(0.92)

            VStack(spacing: 7) {
                Image(systemName: message == nil ? "bolt.horizontal.circle" : "exclamationmark.triangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.warn.opacity(0.14)))
                    .overlay(Circle().stroke(Theme.warn.opacity(0.30), lineWidth: 1))
                    .padding(.bottom, 3)

                Text(message == nil ? "Session ended" : "Connection lost")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)

                Text(message ?? "The PTY closed. tmux keeps the session running on the Mac.")
                    .font(.mono(11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button { reconnect() } label: {
                    Text("Reconnect")
                        .font(.mono(13.5, .semibold))
                        .foregroundStyle(Theme.onLive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                .fill(Theme.live)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 11)

                Button { leave() } label: {
                    Text(isRegular ? "Pick another session" : "Back to sessions")
                        .font(.mono(13.5))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                .stroke(Theme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(width: isRegular ? 340 : 280)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
        }
        .transition(.opacity)
    }

    private func attachFailed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Can't Attach", systemImage: "xmark.octagon")
        } description: {
            Text(message).font(.mono(12))
        } actions: {
            Button("Try Again") { reconnect() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.live)
                .foregroundStyle(Theme.onLive)
        }
        .tint(Theme.link)
    }

    // MARK: Derived state

    private var isLive: Bool {
        if case .live = terminal?.phase { return true }
        return false
    }

    private func isConnecting(_ terminal: TerminalSession) -> Bool {
        if case .connecting = terminal.phase { return true }
        return false
    }

    private var statusDotKind: StatusDot.Kind {
        if setupError != nil { return .warn }
        switch terminal?.phase {
        case .live: return .live
        case .connecting: return .warn
        case .closed, .none: return .idle
        }
    }

    private var statusLabel: String {
        if setupError != nil { return "unavailable" }
        switch terminal?.phase {
        case .live: return model.config.name.isEmpty ? model.config.host : model.config.name
        case .connecting, .none: return "attaching…"
        case .closed(let message): return message == nil ? "detached" : "disconnected"
        }
    }

    // MARK: Lifecycle

    /// "Back": pop the stack on the phone, clear the detail column on iPad
    /// (where there is nothing to pop back to — the list is already on screen).
    private func leave() {
        if isRegular {
            model.selectedSessionName = nil
        } else {
            dismiss()
        }
    }

    private func reconnect() {
        terminal?.stop()
        terminal = nil
        setupError = nil
        generation += 1
        setup()
    }

    private func setup() {
        guard terminal == nil, setupError == nil else { return }
        guard let credential = SettingsStore().loadCredential(for: model.config) else {
            setupError = "No stored credential."
            return
        }
        // `env` injects Homebrew onto PATH; `exec` replaces the shell so a
        // clean tmux detach closes the channel.
        let command = "exec env \(TmuxService.pathPrefix) tmux attach -t \(TmuxService.quote(sessionName))"
        terminal = TerminalSession(config: model.config, credential: credential, startupCommand: command)
    }
}

// MARK: - Chrome pieces

/// A 2pt rail directly under the navigation bar: solid green while live, a
/// pulsing blue sweep while attaching, amber once the channel is gone.
private struct StatusRail: View {
    let phase: TerminalSession.Phase?
    var hasSetupError: Bool
    @State private var pulsing = false

    var body: some View {
        Rectangle()
            .fill(fill)
            .frame(height: 2)
            .opacity(isConnecting ? (pulsing ? 1 : 0.3) : 1)
            .animation(
                isConnecting ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true) : .default,
                value: pulsing
            )
            .animation(.easeInOut(duration: 0.25), value: phase)
            .onAppear { pulsing = true }
    }

    private var isConnecting: Bool {
        guard !hasSetupError else { return false }
        if case .connecting = phase { return true }
        return phase == nil
    }

    private var fill: Color {
        if hasSetupError { return Theme.warn.opacity(0.55) }
        switch phase {
        case .live: return Theme.live.opacity(0.8)
        case .connecting, .none: return Theme.link
        case .closed: return Theme.warn.opacity(0.55)
        }
    }
}

/// Three phosphor dots breathing in sequence — the "attaching" motif.
private struct PulsingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.live)
                    .frame(width: 9, height: 9)
                    .opacity(animating ? 1 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.65)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
