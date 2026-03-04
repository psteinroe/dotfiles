#!/bin/bash
# Claude Code hook: prevent sleep only while Claude is actively working
# UserPromptSubmit → start caffeinate, Stop/Notification → kill it
# Per-session PID file so concurrent sessions don't conflict

set -euo pipefail

EVENT_JSON=$(cat)
EVENT=$(echo "$EVENT_JSON" | jq -r '.hook_event_name // empty')
SESSION_ID=$(echo "$EVENT_JSON" | jq -r '.session_id // empty')

PIDDIR="/tmp/claude-caffeinate"
mkdir -p "$PIDDIR"
PIDFILE="$PIDDIR/$SESSION_ID.pid"

_kill_caffeinate() {
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
}

case "$EVENT" in
  UserPromptSubmit)
    _kill_caffeinate
    caffeinate -di &
    echo $! > "$PIDFILE"
    ;;
  Stop|Notification)
    _kill_caffeinate
    ;;
esac
