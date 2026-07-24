# Notifications over Brrr

Real **background** push for "a tmux session needs your attention" — even when
RemoteSSH is closed — using [Brrr](https://brrr.simonbs.dev) (by Simon B.
Støvring), which you already have installed (`dk.simonbs.brrr`).

## Why Brrr

iOS won't let RemoteSSH hold a live SSH socket in the background, so the app
can't push to itself. Brrr is a tiny native app whose whole job is to turn an
HTTP webhook into an APNs push on your devices. So:

```
Mac: tmux-notify.sh  ──(HTTPS POST + Bearer secret)──▶  Brrr webhook
                                                          │ APNs
                                                          ▼
                                              iPhone: Brrr shows the notification
```

The Mac watcher detects the "needs attention" condition; Brrr does the reliable
background delivery. No server to run, no APNs certificate.

## 1. Create a Brrr webhook

In the Brrr app → add a webhook. Brrr gives you a **secret**; requests go to
`https://api.brrr.now/v1/send` with `Authorization: Bearer <secret>` (or the
secret-in-URL form `https://api.brrr.now/v1/<secret>`). Set `BRRR_API_URL` to
whichever your webhook uses.

The watcher sends a JSON payload (Brrr API fields):

| Field | What we send |
|-------|--------------|
| `title` | `<session> needs attention` |
| `message` | last non-empty pane line |
| `open_url` | `remotessh://open/<session>` — **taps deep-link into RemoteSSH** |
| `image_url` | `$BRRR_ICON_URL` (optional notification image) |
| `interruption_level` | `time-sensitive` (breaks through Focus) |
| `thread_id` | `remotessh-<session>` (groups per session) |

### Notification icon (`image_url`)

Brrr shows `image_url` (a public HTTPS image) in the notification. A ready-made
RemoteSSH icon is committed at [`assets/notification-icon.png`](../assets/notification-icon.png).
Host it on any public URL and set `BRRR_ICON_URL` in the plist. Easy options:

- **GitHub**: push the repo, use the raw URL
  `https://raw.githubusercontent.com/<you>/RemoteSSH/main/assets/notification-icon.png`.
- **Cloudflare** R2 (public bucket) or Pages — upload the PNG, use its URL.

Leave `BRRR_ICON_URL` empty to send notifications without an image.

## 2. Store the secret in the Keychain (not in any file)

```sh
security add-generic-password \
  -a "$USER" \
  -s "remotessh-brrr-webhook-secret" \
  -w 'PASTE-YOUR-BRRR-SECRET'
```

The watcher reads it back with `security find-generic-password … -w`. (You can
instead export `BRRR_WEBHOOK_SECRET`, but Keychain is cleaner.)

## 3. Install the LaunchAgent

```sh
cp scripts/com.danobat.remotessh.notify.plist ~/Library/LaunchAgents/
```

Edit the copy:
- `ProgramArguments` → absolute path to `scripts/tmux-notify.sh`
- `BRRR_API_URL` → your webhook URL
- `TMUX_BIN` → `which tmux` (e.g. `/opt/homebrew/bin/tmux`)

Then load it:

```sh
launchctl load ~/Library/LaunchAgents/com.danobat.remotessh.notify.plist
# reload after edits:
launchctl unload ~/Library/LaunchAgents/com.danobat.remotessh.notify.plist && \
launchctl load   ~/Library/LaunchAgents/com.danobat.remotessh.notify.plist
```

Logs: `/tmp/remotessh-notify.log` and `/tmp/remotessh-notify.err`.

## 4. Test it

Fire a one-off notification to confirm the webhook + secret work:

```sh
SECRET=$(security find-generic-password -a "$USER" -s remotessh-brrr-webhook-secret -w)
curl -fsS -X POST "$BRRR_API_URL" \
  -H "Authorization: Bearer $SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "demo needs attention",
    "message": "hello from RemoteSSH",
    "open_url": "remotessh://open/demo",
    "interruption_level": "time-sensitive"
  }'
```

Tapping that notification should open RemoteSSH straight into the `demo` session.

Then, to test the watcher end-to-end: run a command in a tmux session, let it go
quiet for `SILENCE_SECS`, and you should get a push.

## 5. Tuning

Set these in the plist's `EnvironmentVariables`:

| Var | Default | Meaning |
|-----|---------|---------|
| `SILENCE_SECS` | `20` | Quiet-after-activity threshold → "waiting for you" |
| `POLL_SECS` | `5` | How often the watcher checks each pane |
| `ATTENTION_REGEX` | y/N, "Do you want", "Press ENTER"… | Pane text that always triggers (e.g. Claude Code approval prompts) |
| `BRRR_KEYCHAIN_SERVICE` | `remotessh-brrr-webhook-secret` | Keychain service holding the secret |

For Claude Code sessions specifically, the silence trigger catches "auto mode"
pausing for your input; add app-specific prompts to `ATTENTION_REGEX` for
instant matches.

## Fallback: ntfy

The same script still supports [ntfy](https://ntfy.sh) — leave `BRRR_API_URL`
unset and set `NTFY_TOPIC`. ntfy's `Click:` header deep-links into RemoteSSH via
`remotessh://open/<session>`; the Brrr path opens the Brrr app instead.
