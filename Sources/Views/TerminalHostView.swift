import SwiftUI
import SwiftTerm

/// Wraps SwiftTerm's `TerminalView` and wires it to a `TerminalSession`:
/// host output feeds the emulator, keystrokes/resizes flow back out over SSH.
struct TerminalHostView: UIViewRepresentable {
    let session: TerminalSession

    func makeUIView(context: Context) -> TerminalView {
        let terminalView = TerminalView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator
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
