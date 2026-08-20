import AppIntents

/// Makes `SendTmuxCommandIntent` discoverable in Shortcuts, Spotlight, and
/// Siri without the person having to build the shortcut from scratch.
struct RemoteSSHShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendTmuxCommandIntent(),
            phrases: [
                "Send a command with \(.applicationName)",
                "Run a tmux command with \(.applicationName)",
            ],
            shortTitle: "Send tmux Command",
            systemImageName: "terminal"
        )
    }
}
