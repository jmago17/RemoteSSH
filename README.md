# RemoteSSH

A SwiftUI iOS app that treats each **tmux session like a chat thread**: the list
view is your "conversations," and tapping one opens that session's pane.

Working name: *TmuxChat*. Product/bundle name: **RemoteSSH**
(`com.danobat.RemoteSSH`).

## Status — Phases 1–2 ✅

- SwiftUI session list backed by Citadel SSH `exec` calls
  (`tmux list-sessions` + `capture-pane`).
- Foreground polling (configurable interval); pull-to-refresh.
- Unread dot when a pane changed since you last opened it.
- Tap a session → full **interactive SwiftTerm terminal** over a live SSH PTY
  (`tmux attach`); typing works, resizes on rotation/keyboard.
  - On-screen special keys: **Shift+Tab** (`ESC[Z`), plus an Esc/Tab/Ctrl-C menu.
  - **Reconnect** if the attach drops (also auto-reconnects on foreground return).
- Session management: **create** (`+`), **kill**, **rename** (swipe actions),
  and **Restore Saved Sessions** via tmux-resurrect (toolbar menu + empty state).
- Settings: host / username / port, password *or* ed25519 private key,
  poll interval. Secret stored in the **iOS Keychain**, never on disk.

No notifications yet — see the roadmap below.

## Roadmap

| Phase | Scope | Status |
|------|-------|--------|
| 1 | SwiftUI list + Citadel exec, create/kill/rename, foreground polling | ✅ |
| 2 | SwiftTerm interactive `tmux attach` (typing), PTY resize, on-screen keys | ✅ |
| — | Reconnect on drop + auto-reconnect on foreground | ✅ |
| — | tmux-resurrect **Restore** | ✅ |
| 4 | **Notifications**: ntfy.sh bridge + Mac LaunchAgent watcher (`scripts/tmux-notify.sh`); in-app foreground subscription + deep-links | ✅ |
| 5 | Host-key TOFU pinning | ✅ |
| 5 | In-app ed25519 key generation | ✅ |
| 5 | App icon (Icon Composer), device signing | ✅ |
| 5 | **Multi-host** support (add/edit/delete/switch hosts) | ✅ |
| 5 | Terminal font-size control | ✅ |
| — | **Background push via Brrr** (Mac watcher → Brrr webhook → APNs) | ✅ |
| — | Copy/paste selection polish, scrollback search | ⬜ |

### Notifications setup

**Recommended: Brrr** — real background push via the Brrr app (works when
RemoteSSH is closed). Full guide: [`docs/notifications-brrr.md`](docs/notifications-brrr.md).
In short: create a Brrr webhook, store its secret in the Keychain, set
`BRRR_API_URL` in `scripts/com.danobat.remotessh.notify.plist`, and `launchctl
load` it.

**Fallback: ntfy** — leave `BRRR_API_URL` unset and set `NTFY_TOPIC`. The in-app
Settings → Notifications subscribes in the foreground and deep-links via
`remotessh://open/<session>`.

## Confirmed decisions

- **Personal sideload only** (via Xcode), no App Store — so no distribution
  signing / privacy-manifest work is set up.
- **No push in v1** — start without it; add ntfy.sh in Phase 4.
- **Single active host for now**, but `SSHConnectionConfig` already carries a
  UUID `id` so multi-host is an additive change, not a schema break.

## Requirements

- **Xcode 27 beta** (`/Applications/Xcode-beta.app`) — the Mac runs macOS 27,
  so Xcode 26 will not run here.
- iOS 26 minimum deployment target (built against the iOS 27 SDK).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is
  generated from `project.yml` and is **not** committed.

## Build & run

```sh
# Regenerate the Xcode project after any file add/remove or project.yml change
xcodegen generate

# Always point at the Xcode 27 beta toolchain
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

# Build for the simulator
xcodebuild -project RemoteSSH.xcodeproj -scheme RemoteSSH \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Or just open `RemoteSSH.xcodeproj` in Xcode 27 beta and run.

## Dependencies (SPM)

- [Citadel](https://github.com/orlandos-nl/Citadel) `~> 0.12.1` — pure-Swift
  SwiftNIO SSH client (auth, `exec`, and interactive PTY via `withPTY`).
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) `~> 1.15.0` — terminal
  emulator UIView for the interactive attach view.

## Architecture

```
Sources/
  App/            RemoteSSHApp — @main entry
  Models/         SSHConnectionConfig, SSHCredential, TmuxSession
  Services/
    SSHConnector      Shared connect + auth (password / ed25519). Nonisolated.
    RemoteShell       Non-Sendable Citadel wrapper (connect / run / disconnect).
                      Lives only inside a nonisolated async scope.
    TmuxService       Owns each connect→work→disconnect cycle; builds/parses
                      tmux commands. Returns only Sendable values.
    SSHTerminalRunner Nonisolated driver for the interactive PTY (`withPTY`):
                      pumps host output out, forwards keystrokes/resizes in.
    KeychainStore     Generic-password Keychain wrapper.
    SettingsStore     Config in UserDefaults, secret in Keychain.
  ViewModels/
    SessionListModel  @MainActor @Observable; polling + actions.
    TerminalSession   @MainActor bridge to SSHTerminalRunner via Sendable streams.
  Views/
    SessionListView, SessionRowView, SettingsView,
    SessionThreadView (Peek/Attach toggle), ScrollbackView (peek),
    TerminalScreen + TerminalHostView (SwiftTerm attach)
```

### Concurrency note

The Citadel `SSHClient` is non-Sendable. To stay clean under Swift 6 strict
concurrency, all SSH work is confined to nonisolated async functions in
`TmuxService`; the `@MainActor` view model only ever passes `Sendable`
config/credential values in and receives `Sendable` results back. Never store a
`RemoteShell`/`SSHClient` on an actor or capture it across an isolation boundary.
