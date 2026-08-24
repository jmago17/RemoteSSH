#!/bin/sh
#
# remotessh-notify.sh — push a Brrr notification when a coding agent finishes
# a turn in a tmux session, or when it stops to ask for permission.
#
# Serves BOTH Claude Code (~/.claude/settings.json) and Codex
# (~/.codex/config.toml). They spell the events almost identically — stdin
# JSON, hook_event_name, Stop, last_assistant_message — so one script covers
# both. The one divergence: Codex's permission event is PermissionRequest,
# Claude's is Notification plus a notification_type.
#
# NOTE for Codex: this is registered under [[hooks.*]], NOT under `notify`.
# `notify` takes a single program and is already taken by Codex Computer Use;
# claiming it would silently break that.
#
# WHY THIS EXISTS
# ---------------
# RemoteSSH's original watcher (scripts/tmux-notify.sh in the repo) guessed at
# "Claude finished" by watching a pane go quiet for 20s and grepping for words.
# A quiet pane is ambiguous: it can mean "done", "thinking", or "waiting for
# you". Claude Code publishes the real event, so this asks it instead of
# guessing at its output.
#
# WHY IT LIVES HERE AND NOT IN THE REPO
# -------------------------------------
# ~/Documents is inside iCloud Drive, which evicts files: an evicted hook is a
# 0-byte file and dies silently, taking every notification with it. The
# canonical copy belongs in the repo for history; the copy that RUNS lives
# here, outside iCloud.
#
# INSTALL
#   1. Create a webhook in the Brrr app; it gives you a secret.
#   2. security add-generic-password -a "$USER" \
#        -s "remotessh-brrr-webhook-secret" -w 'PASTE-YOUR-BRRR-SECRET'
#      (choose "Always Allow" the first time macOS prompts, or the keychain
#      re-locking will silently kill notifications)
#   3. Wire it in ~/.claude/settings.json under hooks.Stop and
#      hooks.Notification / hooks.UserPromptSubmit.
#
# Never exits non-zero: a notifier must not be able to break Claude Code.

LOG="$HOME/.claude/hooks/remotessh-notify.log"
BRRR_API_URL="${BRRR_API_URL:-https://api.brrr.now/v1/send}"
BRRR_KEYCHAIN_SERVICE="${BRRR_KEYCHAIN_SERVICE:-remotessh-brrr-webhook-secret}"
BRRR_ICON_URL="${BRRR_ICON_URL:-https://remotessh-icon.pages.dev/notification-icon.png}"
SECRETS_ENV="${REMOTESSH_SECRETS_ENV:-$HOME/.codex/secrets/cloudflare.env}"

# Absolute paths throughout: a hook does not inherit an interactive PATH, and
# Homebrew is not on the default one.
TMUX_BIN="${TMUX_BIN:-/opt/homebrew/bin/tmux}"
CURL=/usr/bin/curl
JQ=/usr/bin/jq
SECURITY=/usr/bin/security

# Turns shorter than this are the user sitting at the Mac having a
# conversation — notifying those is pure noise. Long ones are the case this
# whole feature exists for: you walked away and it finished without you.
MIN_TURN_SECONDS="${REMOTESSH_MIN_TURN_SECONDS:-60}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null; }

# Claude Code and Codex's [[hooks.*]] both deliver JSON on stdin, but some
# Codex builds pass it as argv[1] instead. Accept either rather than find out
# the hard way that half the events were arriving empty.
if [ -n "$1" ]; then payload_json="$1"; else payload_json=$(cat); fi
[ -n "$payload_json" ] || exit 0

event=$(printf '%s' "$payload_json" | "$JQ" -r '.hook_event_name // .type // empty' 2>/dev/null)
session_id=$(printf '%s' "$payload_json" | "$JQ" -r '.session_id // .sessionId // empty' 2>/dev/null)

# --- Subagent guard --------------------------------------------------------
#
# `agent_id` is present ONLY when the hook fires inside a subagent (the Task
# tool). Its Stop is not the main thread's Stop: without this, every subagent
# that finishes announces "it's done" while the real turn keeps working — and
# worse, would write `idle` over a live `working` state.
if [ -n "$(printf '%s' "$payload_json" | "$JQ" -r '.agent_id // empty' 2>/dev/null)" ]; then
    exit 0
fi

# --- Which tmux session is this? -------------------------------------------
#
# Hooks run without a controlling terminal but DO inherit the environment of
# the `claude` process, which tmux stamps with TMUX_PANE. No TMUX_PANE means
# this Claude Code isn't running in tmux — an ad-hoc session, an agent — and
# RemoteSSH has nothing to deep-link to, so stay silent.
[ -n "$TMUX_PANE" ] || exit 0
[ -x "$TMUX_BIN" ] || { log "tmux not found at $TMUX_BIN"; exit 0; }

session=$("$TMUX_BIN" display-message -p -t "$TMUX_PANE" '#S' 2>/dev/null)
[ -n "$session" ] || exit 0

# --- State file ------------------------------------------------------------
#
# The part RemoteSSH reads. Notifications are fire-and-forget; this is the
# durable answer to "what is this session doing right now?", so the app can
# stop inferring it from the shape of the terminal.
#
# One file per PANE, not per session: two agents in two panes of the same tmux
# session would otherwise overwrite each other. The tmux session name travels
# inside the JSON, which is what the app matches on.
#
# Written atomically (write to a temp file, then `mv` within the same
# filesystem) so the app can never read half a record.
STATE_DIR="$HOME/.remotessh/state"
pane_key=$(printf '%s' "$TMUX_PANE" | /usr/bin/tr -c 'A-Za-z0-9' '_')

write_state() {
    # $1 = state, $2 = last_message, $3 = question
    /bin/mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    now=$(date +%s)
    started=$(cat "${TMPDIR:-/tmp}/remotessh-turn-${session_id:-unknown}" 2>/dev/null)
    "$JQ" -n -c \
        --arg pane "$TMUX_PANE" \
        --arg session "$session" \
        --arg agent "$agent_kind" \
        --arg state "$1" \
        --arg last "$2" \
        --arg question "$3" \
        --arg sid "${session_id:-}" \
        --argjson since "${started:-$now}" \
        --argjson updated "$now" \
        '{v:1, pane:$pane, session:$session, agent:$agent, state:$state,
          since:$since, updated:$updated, session_id:$sid,
          last_message:(if $last == "" then null else $last end),
          question:(if $question == "" then null else $question end)}' \
        > "$STATE_DIR/.$pane_key.tmp" 2>/dev/null \
        && /bin/mv -f "$STATE_DIR/.$pane_key.tmp" "$STATE_DIR/$pane_key.json" 2>/dev/null
    return 0
}

# Codex and Claude Code share this script; the app shows the product name.
case "${CODEX_HOME:-}${CODEX_SANDBOX:-}" in
    ?*) agent_kind="codex" ;;
    *)  agent_kind=$(printf '%s' "$payload_json" | "$JQ" -r 'if .type then "codex" else "claude-code" end' 2>/dev/null) ;;
esac
[ -n "$agent_kind" ] || agent_kind="claude-code"

# --- Turn-start stamp, written by the UserPromptSubmit hook -----------------
stamp_file="${TMPDIR:-/tmp}/remotessh-turn-${session_id:-unknown}"

case "$event" in
    SessionStart)
        # A fresh session in this pane: drop whatever the last one left behind.
        rm -f "$stamp_file" 2>/dev/null
        write_state idle "" ""
        exit 0
        ;;
    SessionEnd)
        rm -f "$STATE_DIR/$pane_key.json" "$stamp_file" 2>/dev/null
        exit 0
        ;;
    UserPromptSubmit|task_started|Start)
        date +%s > "$stamp_file" 2>/dev/null
        write_state working "" ""
        exit 0
        ;;
esac

# From here on the event ends a turn one way or another. State is written
# BEFORE the notification guards below, on purpose: "you're already looking at
# it" and "that turn was too short to be worth a ping" are reasons not to
# *interrupt* you. They are not reasons to let the app keep showing a stale
# state.
case "$event" in
    Stop|agent-turn-complete)
        last=$(printf '%s' "$payload_json" \
            | "$JQ" -r '(.last_assistant_message // "") | gsub("\\s+"; " ") | .[0:1200]' 2>/dev/null)
        write_state idle "$last" ""
        ;;
    StopFailure)
        # The API-error hook. It fires while the session stays alive, unlike
        # Stop — so without handling it a failed turn leaves the app showing
        # "working" forever, waiting for a Stop that is never coming.
        write_state error "" ""
        ;;
    Notification|PermissionRequest)
        q=$(printf '%s' "$payload_json" \
            | "$JQ" -r '(.message // .tool_input.description // .tool_name // "") | gsub("\\s+"; " ") | .[0:400]' 2>/dev/null)
        write_state awaiting "" "$q"
        ;;
esac

# --- Are you already looking at it? ----------------------------------------
#
# A tmux client attached to this session means someone has it open on screen,
# so the notification would be telling you what you can already see.
attached=$("$TMUX_BIN" display-message -p -t "$TMUX_PANE" '#{session_attached}' 2>/dev/null)
if [ "${attached:-0}" != "0" ]; then
    log "skip ($session): $attached client(s) attached"
    exit 0
fi

case "$event" in
    Stop)
        started=$(cat "$stamp_file" 2>/dev/null)
        rm -f "$stamp_file" 2>/dev/null
        if [ -n "$started" ]; then
            elapsed=$(( $(date +%s) - started ))
            if [ "$elapsed" -lt "$MIN_TURN_SECONDS" ]; then
                log "skip ($session): turn took ${elapsed}s, under ${MIN_TURN_SECONDS}s"
                exit 0
            fi
        fi

        subtitle="ha terminado"
        # last_assistant_message is the real final text — better than scraping
        # the pane, which Claude Code has already hard-wrapped and boxed.
        body=$(printf '%s' "$payload_json" \
            | "$JQ" -r '(.last_assistant_message // "") | gsub("\\s+"; " ") | .[0:180]' 2>/dev/null)
        [ -n "$body" ] || body="Turno terminado."
        # Not time-sensitive: "it finished" must not pierce Sleep Focus at 3am.
        level="active"
        ;;
    StopFailure)
        # State is already recorded above. No push: an API error is not
        # something you can act on from the phone, and it often retries.
        exit 0
        ;;
    Notification|PermissionRequest)
        # Claude Code fires Notification for several things and names the kind
        # in notification_type; Codex fires PermissionRequest and carries no
        # such field. Filter only when there is something to filter on.
        kind=$(printf '%s' "$payload_json" | "$JQ" -r '.notification_type // empty' 2>/dev/null)
        if [ -n "$kind" ]; then
            case "$kind" in
                permission_prompt|agent_needs_input) ;;
                *) exit 0 ;;
            esac
        fi
        subtitle="espera tu respuesta"
        body=$(printf '%s' "$payload_json" \
            | "$JQ" -r '(.message // .tool_input.description // .tool_name // "") | gsub("\\s+"; " ") | .[0:180]' 2>/dev/null)
        [ -n "$body" ] || body="Necesita tu respuesta."
        # This one CAN interrupt: it is blocking work until you answer.
        level="time-sensitive"
        ;;
    *)
        exit 0
        ;;
esac

# --- Secret -----------------------------------------------------------------
secret="${BRRR_WEBHOOK_SECRET:-}"
if [ -z "$secret" ]; then
    secret=$("$SECURITY" find-generic-password -a "${USER:-$(id -un)}" \
        -s "$BRRR_KEYCHAIN_SERVICE" -w 2>/dev/null)
fi
if [ -z "$secret" ] && [ -r "$SECRETS_ENV" ]; then
    # Last resort, and on this Mac the one that actually works. The keychain
    # re-locks itself, and `security` in a hook has no window to ask for the
    # password with, so it fails with "User interaction is not allowed" —
    # silently, at exactly the moment a notification was due. This file already
    # holds BRRR_SECRET for other tooling, so reading it here adds no new
    # exposure; it is chmod 600 and outside iCloud.
    secret=$(/usr/bin/grep -m1 '^export BRRR_SECRET=' "$SECRETS_ENV" 2>/dev/null \
        | /usr/bin/sed -e 's/^export BRRR_SECRET=//' -e 's/^["'"'"']//' -e 's/["'"'"']$//')
fi

if [ -z "$secret" ]; then
    # Logged rather than swallowed: a silently missing secret looks exactly
    # like "the notification never fired", and that cost an evening once.
    log "no secret (keychain service $BRRR_KEYCHAIN_SERVICE, nor $SECRETS_ENV) — nothing sent for $session"
    exit 0
fi

encoded_session=$(printf '%s' "$session" \
    | /usr/bin/python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))' 2>/dev/null)
[ -n "$encoded_session" ] || encoded_session="$session"

payload=$("$JQ" -n \
    --arg title "$session" \
    --arg subtitle "$subtitle" \
    --arg message "$body" \
    --arg open_url "remotessh://open/$encoded_session" \
    --arg level "$level" \
    --arg thread "remotessh-$session" \
    --arg icon "$BRRR_ICON_URL" \
    '{title: $title, subtitle: $subtitle, message: $message, open_url: $open_url,
      interruption_level: $level, thread_id: $thread, image_url: $icon}')

if "$CURL" --fail --silent --show-error --max-time 15 --retry 3 --retry-delay 5 \
    -X POST "$BRRR_API_URL" \
    -H "Authorization: Bearer $secret" \
    -H "Content-Type: application/json" \
    --data-binary "$payload" >> "$LOG" 2>&1
then
    log "sent ($session): $subtitle"
else
    log "FAILED ($session): curl exit $?"
fi

exit 0
