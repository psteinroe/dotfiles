#!/bin/bash
# Claude Code hook: sends macOS notification + updates neovim titlestring
# Receives hook event JSON on stdin (UserPromptSubmit, Stop, Notification)

set -euo pipefail

EVENT_JSON=$(cat)
EVENT=$(echo "$EVENT_JSON" | jq -r '.hook_event_name // empty')
CWD=$(echo "$EVENT_JSON" | jq -r '.cwd // empty')
PROJECT=$(basename "${CWD:-unknown}")

case "$EVENT" in
  UserPromptSubmit)
    STATUS="working"
    ;;
  Stop)
    TITLE="$PROJECT"
    MESSAGE="Task completed"
    STATUS="done"
    ;;
  Notification)
    TITLE="$PROJECT"
    MESSAGE=$(echo "$EVENT_JSON" | jq -r '.message // "Needs attention"')
    STATUS="done"
    ;;
  *)
    exit 0
    ;;
esac

# macOS desktop notification (skip for working — too noisy)
if [ "$STATUS" != "working" ]; then
  osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" sound name \"Glass\"" 2>/dev/null || true
fi

# Update neovim titlestring via parent socket
if [ -n "${NVIM:-}" ]; then
  timeout 2 nvim --server "$NVIM" --remote-expr "luaeval('require(\"config.status-title\").set(\"$STATUS\")')" 2>/dev/null || true
fi
