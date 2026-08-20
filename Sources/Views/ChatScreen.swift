import SwiftUI

/// A session read as a conversation: what the user typed on the right, what the
/// machine answered on the left, and a composer to send the next command.
///
/// This sits *on top of* the terminal rather than replacing it. Anything
/// interactive — vim, htop, a password prompt, a curses menu — can't be read as
/// turns and can't be driven from a one-line composer, so the real
/// `TerminalScreen` is always one tap away in the toolbar.
struct ChatScreen: View {
    /// Identified by name for the same reason `TerminalScreen` is: polling
    /// replaces every `TmuxSession` value a few seconds later.
    let sessionName: String
    @Bindable var model: SessionListModel

    @State private var chat: ChatSessionModel?
    /// Output blocks that the user has asked to see in full.
    @State private var expandedTurns: Set<Int> = []
    @State private var showingTerminal = false
    @FocusState private var composerFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegular: Bool { horizontalSizeClass.isRegular }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(chat?.errorMessage == nil ? Theme.live.opacity(0.8) : Theme.warn.opacity(0.55))
                .frame(height: 2)

            if let chat {
                content(chat)
                composer(chat)
            } else {
                Spacer()
                ProgressView().tint(Theme.textTertiary)
                Spacer()
            }
        }
        .background(Theme.bg)
        .navigationTitle(sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .phosphorNavigationBar()
        .toolbar {
            ToolbarItem(placement: .principal) { titleBlock }
            ToolbarItem(placement: .topBarTrailing) { terminalButton }
        }
        .task {
            model.markRead(sessionName)
            if chat == nil {
                chat = ChatSessionModel(sessionName: sessionName, config: model.config)
            }
            await chat?.refresh()
        }
        // The terminal is a *mode*, not a sibling screen: you drop into it,
        // do the interactive thing, and come back. A cover says that plainly,
        // works identically on the split view's detail column, and gives one
        // unambiguous moment — dismissal — to re-read the pane.
        .fullScreenCover(isPresented: $showingTerminal) {
            terminalCover
        }
        .onChange(of: showingTerminal) { _, isShowing in
            // Back from the terminal: the user has almost certainly run
            // something there, so the transcript is stale.
            if !isShowing { Task { await chat?.refresh() } }
        }
    }

    // MARK: Chrome

    /// Matches `TerminalScreen`'s inline title exactly, so moving between the
    /// two reads as one screen changing modes rather than two screens.
    private var titleBlock: some View {
        VStack(spacing: 1) {
            Text(sessionName)
                .font(.mono(15, .semibold))
                .kerning(-0.3)
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            HStack(spacing: 5) {
                StatusDot(kind: chat?.errorMessage == nil ? .live : .warn, size: 6)
                Text(hostLabel.uppercased())
                    .font(.mono(9.5, .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The escape hatch. A `>_` cap rather than a menu item: it has to be
    /// reachable without thinking, because it's what you reach for the moment
    /// the conversation stops being able to help.
    private var terminalButton: some View {
        Button {
            showingTerminal = true
        } label: {
            HStack(spacing: 5) {
                Text(">_")
                    .font(.mono(12, .bold))
                    .foregroundStyle(Theme.live)
                if isRegular {
                    Text("Terminal")
                        .font(.mono(11, .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel("Open terminal")
        .keyboardShortcut("t", modifiers: .command)
    }

    private var terminalCover: some View {
        NavigationStack {
            TerminalScreen(sessionName: sessionName, model: model)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { showingTerminal = false }
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
        }
        .tint(Theme.link)
    }

    // MARK: Transcript

    @ViewBuilder
    private func content(_ chat: ChatSessionModel) -> some View {
        if chat.isLoadingInitial {
            loading
        } else if let error = chat.errorMessage, chat.transcript.turns.isEmpty {
            failed(error, chat: chat)
        } else if chat.isEmpty {
            emptyState
        } else {
            transcriptList(chat)
        }
    }

    private func transcriptList(_ chat: ChatSessionModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13) {
                    if let fallback = chat.transcript.fallback {
                        FallbackNote(fallback: fallback) { showingTerminal = true }
                            .padding(.bottom, 2)
                    }

                    ForEach(chat.transcript.turns) { turn in
                        TranscriptTurnView(
                            turn: turn,
                            isExpanded: expandedTurns.contains(turn.id),
                            onToggleExpanded: { toggle(turn.id) }
                        )
                        .id(turn.id)
                    }

                    // The command is already gone from the composer, so without
                    // this it would vanish until the pane catches up.
                    if let pending = chat.pendingCommand {
                        PendingCommandBubble(command: pending).id(pendingID)
                    }

                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(.horizontal, isRegular ? 22 : 14)
                .padding(.top, 15)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.transcript) { _, _ in scrollToBottom(proxy) }
            .onChange(of: chat.pendingCommand) { _, _ in scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    private var loading: some View {
        VStack(spacing: 13) {
            Spacer()
            ProgressView().tint(Theme.textTertiary)
            Text("Reading \(sessionName)…")
                .font(.mono(12))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Spacer()
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

            Text("Nothing here yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            Text("This session hasn't printed anything.\nSend a command below, or open the terminal for anything interactive.")
                .font(.mono(12.5))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func failed(_ message: String, chat: ChatSessionModel) -> some View {
        ContentUnavailableView {
            Label("Can't Read This Session", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message).font(.mono(12))
        } actions: {
            Button("Try Again") { Task { await chat.refresh() } }
                .buttonStyle(.borderedProminent)
                .tint(Theme.live)
                .foregroundStyle(Theme.onLive)
            Button("Open Terminal") { showingTerminal = true }
        }
        .tint(Theme.link)
    }

    // MARK: Composer

    private func composer(_ chat: ChatSessionModel) -> some View {
        HStack(alignment: .bottom, spacing: 9) {
            HStack(spacing: 8) {
                Text("$")
                    .font(.mono(13, .medium))
                    .foregroundStyle(Theme.link)

                TextField("Run a command…", text: Binding(
                    get: { chat.draft },
                    set: { chat.draft = $0 }
                ), axis: .vertical)
                    .font(.mono(13))
                    .foregroundStyle(Theme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .onSubmit { submit(chat) }
                    .submitLabel(.send)
                    .disabled(chat.isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Theme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(composerFocused ? Theme.link.opacity(0.55) : Theme.hairline, lineWidth: 1)
            )

            Button {
                submit(chat)
            } label: {
                Group {
                    if chat.isSending {
                        ProgressView().tint(Theme.textTertiary)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(chat.canSend ? Theme.onLive : Theme.textTertiary)
                    }
                }
                .frame(width: 38, height: 38)
                .background(Circle().fill(chat.canSend ? Theme.live : Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .disabled(!chat.canSend)
            .accessibilityLabel("Send command")
        }
        .padding(.horizontal, isRegular ? 22 : 12)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }

    // MARK: Helpers

    private func submit(_ chat: ChatSessionModel) {
        guard chat.canSend else { return }
        Task { await chat.send() }
    }

    private func toggle(_ id: Int) {
        if expandedTurns.contains(id) {
            expandedTurns.remove(id)
        } else {
            expandedTurns.insert(id)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        // A conversation is read from the bottom: the newest turn is the point.
        if animated {
            withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }

    private var hostLabel: String {
        model.config.name.isEmpty ? model.config.host : model.config.name
    }

    private var bottomID: String { "transcript-bottom" }
    private var pendingID: String { "transcript-pending" }
}
