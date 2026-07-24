#!/bin/bash
#
# tmux-notify.sh — watch tmux sessions and push a notification (via ntfy) when a
# session "needs attention". Runs on the Mac as a LaunchAgent; RemoteSSH on the
# phone (or the ntfy app) receives the push.
#
# "Needs attention" = a session that was active and then went SILENT for
# $SILENCE_SECS (a long command finished / Claude Code is waiting on you), or a
# pane matching $ATTENTION_REGEX (approval prompts, y/N, etc.).
#
# Configure via environment (or edit the defaults below):
#   NTFY_SERVER   default https://ntfy.sh
#   NTFY_TOPIC    required — your private topic, e.g. remotessh-a8f3k2 (keep it secret)
#   SILENCE_SECS  default 20   — quiet-after-activity threshold
#   POLL_SECS     default 5
#   ATTENTION_REGEX  extra regex that always triggers (egrep syntax)
#   TMUX_BIN      default $(command -v tmux)
set -u

NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
SILENCE_SECS="${SILENCE_SECS:-20}"
POLL_SECS="${POLL_SECS:-5}"
ATTENTION_REGEX="${ATTENTION_REGEX:-(\\? \\[y/N\\]|\\(y/n\\)|Do you want|Press ENTER|Proceed\\?|approval|waiting for your)}"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux)}"

if [ -z "$NTFY_TOPIC" ]; then
  echo "ERROR: set NTFY_TOPIC (your private ntfy topic)." >&2
  exit 1
fi
if [ -z "$TMUX_BIN" ] || [ ! -x "$TMUX_BIN" ]; then
  echo "ERROR: tmux not found; set TMUX_BIN." >&2
  exit 1
fi

declare -A last_hash last_change notified

now() { date +%s; }

notify() {
  local session="$1" body="$2"
  # Title = session name; Click opens RemoteSSH deep-linked to that session.
  curl -fsS \
    -H "Title: ${session} needs attention" \
    -H "Tags: bell" \
    -H "Click: remotessh://open/$(printf %s "$session" | sed 's/ /%20/g')" \
    -d "${body:-Session is waiting}" \
    "${NTFY_SERVER}/${NTFY_TOPIC}" >/dev/null 2>&1
}

echo "tmux-notify watching (server=$NTFY_SERVER topic=$NTFY_TOPIC silence=${SILENCE_SECS}s)"

while true; do
  # List sessions; skip if no server.
  sessions="$("$TMUX_BIN" list-sessions -F '#S' 2>/dev/null)" || sessions=""
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    pane="$("$TMUX_BIN" capture-pane -p -t "$s" -S -20 2>/dev/null)"
    hash="$(printf %s "$pane" | cksum | awk '{print $1}')"
    lastline="$(printf %s "$pane" | awk 'NF{l=$0} END{print l}')"
    t="$(now)"

    if [ "${last_hash[$s]:-}" != "$hash" ]; then
      # Activity: content changed since last poll.
      last_hash[$s]="$hash"
      last_change[$s]="$t"
      notified[$s]=0
    else
      # Unchanged since last poll.
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
