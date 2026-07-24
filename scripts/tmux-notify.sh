#!/bin/bash
#
# tmux-notify.sh — watch tmux sessions and push a notification when a session
# "needs attention". Delivers via Brrr (real background push, recommended) or
# ntfy. Runs on the Mac as a LaunchAgent.
#
# "Needs attention" = a session that was active and then went SILENT for
# $SILENCE_SECS (a long command finished / Claude Code is waiting on you), or a
# pane matching $ATTENTION_REGEX (approval prompts, y/N, etc.).
#
# Backend (auto: Brrr if BRRR_API_URL is set, else ntfy):
#   Brrr — set BRRR_API_URL (your webhook URL) and the secret via either
#          BRRR_WEBHOOK_SECRET, or the macOS Keychain (see BRRR_KEYCHAIN_SERVICE).
#   ntfy — set NTFY_TOPIC (and optional NTFY_SERVER).
#
# Common config:
#   SILENCE_SECS  default 20   POLL_SECS default 5
#   ATTENTION_REGEX  extra egrep pattern that always triggers
#   TMUX_BIN      default $(command -v tmux)
set -u

BACKEND="${NOTIFY_BACKEND:-}"
BRRR_API_URL="${BRRR_API_URL:-}"
BRRR_KEYCHAIN_SERVICE="${BRRR_KEYCHAIN_SERVICE:-remotessh-brrr-webhook-secret}"
BRRR_ICON_URL="${BRRR_ICON_URL:-}"   # optional public HTTPS image shown in the notification
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
SILENCE_SECS="${SILENCE_SECS:-20}"
POLL_SECS="${POLL_SECS:-5}"
ATTENTION_REGEX="${ATTENTION_REGEX:-(\\? \\[y/N\\]|\\(y/n\\)|Do you want|Press ENTER|Proceed\\?|approval|waiting for your)}"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux)}"

# Pick a backend automatically if not forced.
if [ -z "$BACKEND" ]; then
  if [ -n "$BRRR_API_URL" ]; then BACKEND="brrr"; else BACKEND="ntfy"; fi
fi

if [ -z "$TMUX_BIN" ] || [ ! -x "$TMUX_BIN" ]; then
  echo "ERROR: tmux not found; set TMUX_BIN." >&2; exit 1
fi
if [ "$BACKEND" = "brrr" ] && [ -z "$BRRR_API_URL" ]; then
  echo "ERROR: BACKEND=brrr but BRRR_API_URL is unset." >&2; exit 1
fi
if [ "$BACKEND" = "ntfy" ] && [ -z "$NTFY_TOPIC" ]; then
  echo "ERROR: BACKEND=ntfy but NTFY_TOPIC is unset." >&2; exit 1
fi

now() { date +%s; }

# Brrr webhook secret: env first, else macOS Keychain (never printed).
load_brrr_secret() {
  if [ -n "${BRRR_WEBHOOK_SECRET:-}" ]; then printf '%s' "$BRRR_WEBHOOK_SECRET"; return 0; fi
  /usr/bin/security find-generic-password -a "${USER:-$(id -un)}" -s "$BRRR_KEYCHAIN_SERVICE" -w 2>/dev/null
}

notify_brrr() {
  local session="$1" body="$2" secret payload
  secret="$(load_brrr_secret)"
  if [ -z "$secret" ]; then
    echo "Brrr secret missing (env BRRR_WEBHOOK_SECRET or Keychain service '$BRRR_KEYCHAIN_SERVICE')." >&2
    return 1
  fi
  # Build a JSON payload: title/message, a tap deep-link into RemoteSSH
  # (remotessh://open/<session>), an optional notification image, and a
  # time-sensitive interruption level so it breaks through Focus.
  payload="$(
    SESSION="$session" BODY="${body:-Session is waiting}" IMAGE_URL="$BRRR_ICON_URL" \
    /usr/bin/python3 -c '
import json, os, urllib.parse
s = os.environ["SESSION"]
d = {
    "title": s + " needs attention",
    "message": os.environ["BODY"],
    "open_url": "remotessh://open/" + urllib.parse.quote(s, safe=""),
    "interruption_level": "time-sensitive",
    "thread_id": "remotessh-" + s,
}
iu = os.environ.get("IMAGE_URL") or ""
if iu:
    d["image_url"] = iu
print(json.dumps(d))'
  )"
  /usr/bin/curl --fail --silent --show-error --max-time 15 \
    -X POST "$BRRR_API_URL" \
    -H "Authorization: Bearer $secret" \
    -H "Content-Type: application/json" \
    --data-binary "$payload" >/dev/null 2>&1
}

notify_ntfy() {
  local session="$1" body="$2"
  /usr/bin/curl -fsS \
    -H "Title: ${session} needs attention" \
    -H "Tags: bell" \
    -H "Click: remotessh://open/$(printf %s "$session" | sed 's/ /%20/g')" \
    -d "${body:-Session is waiting}" \
    "${NTFY_SERVER}/${NTFY_TOPIC}" >/dev/null 2>&1
}

notify() {
  case "$BACKEND" in
    brrr) notify_brrr "$1" "$2" ;;
    ntfy) notify_ntfy "$1" "$2" ;;
  esac
}

echo "tmux-notify watching (backend=$BACKEND silence=${SILENCE_SECS}s)"

declare -A last_hash last_change notified

while true; do
  sessions="$("$TMUX_BIN" list-sessions -F '#S' 2>/dev/null)" || sessions=""
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    pane="$("$TMUX_BIN" capture-pane -p -t "$s" -S -20 2>/dev/null)"
    hash="$(printf %s "$pane" | cksum | awk '{print $1}')"
    lastline="$(printf %s "$pane" | awk 'NF{l=$0} END{print l}')"
    t="$(now)"

    if [ "${last_hash[$s]:-}" != "$hash" ]; then
      last_hash[$s]="$hash"; last_change[$s]="$t"; notified[$s]=0
    else
      quiet=$(( t - ${last_change[$s]:-$t} ))
      if [ "${notified[$s]:-0}" -eq 0 ]; then
        if printf %s "$pane" | grep -Eq "$ATTENTION_REGEX"; then
          notify "$s" "$lastline"; notified[$s]=1
        elif [ "$quiet" -ge "$SILENCE_SECS" ] && [ -n "$lastline" ]; then
          notify "$s" "$lastline"; notified[$s]=1
        fi
      fi
    fi
  done <<< "$sessions"
  sleep "$POLL_SECS"
done
