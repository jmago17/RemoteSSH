import SwiftUI
import SwiftTerm

/// Wraps SwiftTerm's `TerminalView` and wires it to a `TerminalSession`:
/// host output feeds the emulator, keystrokes/resizes flow back out over SSH.
struct TerminalHostView: UIViewRepresentable {
    let session: TerminalSession
    var fontSize: CGFloat = 13

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
        // Focus the terminal once so the keyboard appears.
        if !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { _ = uiView.becomeFirstResponder() }
        }
        // Apply font-size changes (reflows the PTY via sizeChanged).
        if abs(uiView.font.pointSize - fontSize) > 0.1 {
            uiView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    final class Coordinator: TerminalViewDelegate {
        let session: TerminalSession
        weak var terminalView: TerminalView?
        var didFocus = false

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
