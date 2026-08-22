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
    /// Gates the kill confirmation. Killing a tmux session is not undoable and
    /// takes whatever was running inside it with it, so it asks first.
    @State private var confirmingKill = false
    /// Width of the transcript column, handed to each output block so it can
    /// size its monospaced text to the columns it actually has. Measured here
    /// rather than per row: every row gets the same column, and a
    /// GeometryReader inside a LazyVStack row is exactly the kind of
    /// self-referential sizing that makes lazy stacks misbehave.
    @State private var transcriptWidth: CGFloat = 0
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
                    // Tap-outside-to-dismiss, the way every messaging app does
                    // it — this replaces a keyboard-toolbar Done button, which
                    // was both ugly and the likely cause of the composer
                    // landing *under* the QuickType bar: a
                    // `ToolbarItemGroup(placement: .keyboard)` hung off a
                    // TextField installs its own input accessory view, and
                    // that view's height fights the keyboard safe-area inset
                    // SwiftUI is already applying to the composer.
                    //
                    // `simultaneousGesture`, not `onTapGesture`: everything
                    // above the composer is full of things that must still
                    // answer the same tap — the "Show all" footer, the Claude
                    // Code banner, "Try Again", selectable text. A plain tap
                    // gesture would swallow them.
                    .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
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
            ToolbarItem(placement: .topBarTrailing) { sessionMenu }
        }
        .confirmationDialog(
            "Kill \(sessionName)?",
            isPresented: $confirmingKill,
            titleVisibility: .visible
        ) {
            Button("Kill Session", role: .destructive) {
                // `model.kill` clears the selection, and the navigation path is
                // derived from it — so this screen closes on its own, in both
                // the pushed and the split-view layout.
                Task { await model.kill(sessionName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Whatever is running in this session is killed with it. tmux can't bring it back.")
        }
        .task {
            model.markRead(sessionName)
            if chat == nil {
                chat = ChatSessionModel(sessionName: sessionName, config: model.config)
            }
            await chat?.refresh()
            chat?.startWatchingClaudeCode()
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
        .onDisappear {
            // One poller per open chat screen is enough; leaving the screen
            // (back, tab switch, terminal cover doesn't count — that's a
            // sheet, not a disappearance) stops it so it doesn't keep polling
            // a session nobody's looking at.
            chat?.stopWatchingClaudeCode()
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
    /// Actions on the session itself, as opposed to on the conversation in it.
    /// Behind a menu rather than on the bar: the only thing in here is
    /// destructive, and a one-tap kill sitting next to the terminal button is
    /// a mis-tap waiting to happen.
    private var sessionMenu: some View {
        Menu {
            Button(role: .destructive) {
                confirmingKill = true
            } label: {
                Label("Kill Session", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Session actions")
    }

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
                    if let agent = chat.transcript.agent {
                        AgentBanner(status: agent) { showingTerminal = true }
                        // The conclusion card is Claude-Code-only on purpose:
                        // `lastConclusion` finds the last turn by Claude Code's
                        // `⏺` marker, and Codex marks its turns with `•`
                        // instead. Feeding a Codex frame through it would
                        // summarise whatever the tail happened to be, so until
                        // there's a verified Codex extractor the card stays
                        // away rather than guess.
                        if agent.agent == .claudeCode {
                            ClaudeCodeConclusionCard(
                                summary: chat.conclusionSummary,
                                isSummarising: chat.isSummarising,
                                errorMessage: chat.summaryError
                            )
                            .padding(.bottom, 2)
                        }
                    } else if let fallback = chat.transcript.fallback {
                        FallbackNote(fallback: fallback) { showingTerminal = true }
                            .padding(.bottom, 2)
                    }

                    ForEach(chat.transcript.turns) { turn in
                        TranscriptTurnView(
                            turn: turn,
                            isExpanded: expandedTurns.contains(turn.id),
                            availableWidth: transcriptWidth,
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
                // Measured on the stack itself, BEFORE the padding modifiers.
                // Order matters and got this wrong once: `.padding()` returns a
                // view *wider* than its content, so measuring after it reports
                // the full screen width and every block is then sized ~28pt too
                // wide — which looks exactly like the bug this is meant to fix.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { transcriptWidth = $0 }
                .padding(.horizontal, isRegular ? 22 : 14)
                .padding(.top, 15)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // `.immediately` rather than `.interactively`: a half-dragged
            // keyboard leaves the composer parked mid-animation, which is
            // exactly the "bubble ends up in the wrong place" state.
            .scrollDismissesKeyboard(.immediately)
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
            // The whole pill focuses, not just the glyphs inside it — tapping
            // the `$` or the padding beside a one-word draft is the same
            // intent as tapping the text. Messaging apps all behave this way.
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .onTapGesture { composerFocused = true }
            .background(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Theme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(composerFocused ? Theme.link.opacity(0.55) : Theme.hairline, lineWidth: 1)
            )

            // While something is running, the send button *becomes* the stop
            // button. Ctrl-C is only meaningful during that window, and a
            // permanent second button would be dead weight the rest of the
            // time. Same position, so the thumb is already there.
            Button {
                if chat.isSending {
                    Task { await chat.interrupt() }
                } else {
                    submit(chat)
                }
            } label: {
                Group {
                    if chat.isSending {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.warn)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(chat.canSend ? Theme.onLive : Theme.textTertiary)
                    }
                }
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(
                        chat.isSending
                            ? Theme.warn.opacity(0.16)
                            : (chat.canSend ? Theme.live : Theme.surfaceRaised)
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Theme.warn.opacity(chat.isSending ? 0.5 : 0), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!chat.canSend && !chat.isSending)
            .accessibilityLabel(chat.isSending ? "Stop the running command" : "Send command")
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
