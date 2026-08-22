import SwiftUI
import SwiftTerm

/// Wraps SwiftTerm's `TerminalView` and wires it to a `TerminalSession`:
/// host output feeds the emulator, keystrokes/resizes flow back out over SSH.
struct TerminalHostView: UIViewRepresentable {
    let session: TerminalSession
    var fontSize: CGFloat = 13
    /// Whether the terminal should hold first responder — i.e. show the
    /// software keyboard. `TerminalScreen` turns this off while the expanded
    /// key panel is up, since the two would otherwise fight for the same
    /// bottom half of the screen.
    var wantsKeyboard: Bool = true

    func makeUIView(context: Context) -> TerminalView {
        let terminalView = TerminalView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator
        terminalView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        // Match the emulator's own canvas to the app's terminal surface so the
        // view reads as part of the screen rather than a pasted-in black box.
        terminalView.nativeBackgroundColor = Theme.terminalBGUI
        terminalView.nativeForegroundColor = Theme.textUI
        terminalView.caretColor = Theme.liveUI
        terminalView.backgroundColor = Theme.terminalBGUI
        // Suppress SwiftTerm's own built-in keyboard accessory row (esc/ctrl/
        // arrows/symbols) -- it duplicates our themed KeyCap rail in
        // TerminalScreen's toolbar, stacking two shortcut rows above the
        // keyboard. Keep only the custom one.
        terminalView.inputAccessoryView = nil
        context.coordinator.terminalView = terminalView

        // Feed host output into the emulator (called on the main actor).
        session.onData = { [weak terminalView] bytes in
            terminalView?.feed(byteArray: bytes[...])
        }

        // Kick off the SSH PTY using the emulator's current geometry; the first
        // `sizeChanged` after layout will correct it.
        let term = terminalView.getTerminal()
        session.start(initialSize: TerminalSize(cols: term.cols, rows: term.rows))

        return terminalView
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        syncKeyboard(uiView, coordinator: context.coordinator)
        // Apply font-size changes (reflows the PTY via sizeChanged).
        if abs(uiView.font.pointSize - fontSize) > 0.1 {
            uiView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

    /// Drives first responder from `wantsKeyboard`, and **only on a change**.
    ///
    /// Two things this deliberately does not do. It doesn't resign via
    /// `UIApplication.sendAction(_:to:nil…)`: that fires at whatever holds
    /// first responder at the time, which is a guess, whereas the terminal
    /// view is the thing we actually mean. And it doesn't re-assert focus on
    /// every `updateUIView`: SwiftUI re-runs this for unrelated reasons (a
    /// font change, a status-rail update), so an unconditional
    /// `becomeFirstResponder` would yank the keyboard back up seconds after
    /// the user dismissed it by some other route.
    ///
    /// The initial focus falls out of the same rule: `appliedKeyboard` starts
    /// `nil`, so the first pass is a change and the keyboard appears.
    /// `DispatchQueue.main.async` because responder changes during a SwiftUI
    /// update pass fight the layout that is still in flight.
    private func syncKeyboard(_ uiView: TerminalView, coordinator: Coordinator) {
        guard coordinator.appliedKeyboard != wantsKeyboard else { return }
        coordinator.appliedKeyboard = wantsKeyboard
        let wants = wantsKeyboard
        DispatchQueue.main.async {
            if wants {
                _ = uiView.becomeFirstResponder()
            } else {
                _ = uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    final class Coordinator: TerminalViewDelegate {
        let session: TerminalSession
        weak var terminalView: TerminalView?
        /// Last value of `wantsKeyboard` actually pushed at the responder
        /// chain. `nil` until the first pass, which is what makes that pass
        /// count as a change and give the terminal its initial focus.
        var appliedKeyboard: Bool?

        init(session: TerminalSession) { self.session = session }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            session.sendUserInput(Array(data))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            session.resize(TerminalSize(cols: newCols, rows: newRows))
        }

        // Unused delegate callbacks (no default implementations in SwiftTerm).
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
