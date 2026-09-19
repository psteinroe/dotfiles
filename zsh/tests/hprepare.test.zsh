#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p \
  "$fixture/home/Developer/example" \
  "$fixture/home/.config/herdr" \
  "$fixture/dotfiles/zsh/functions"
git -C "$fixture/home/Developer/example" init -q
ln -s "$fixture/dotfiles" "$fixture/home/Developer/dotfiles"
print -r -- '[]' > "$fixture/home/.config/herdr/plugins.json"

cp "$repo_root/zsh/functions/_herdr_binary" "$fixture/dotfiles/zsh/functions/_herdr_binary"
cat > "$fixture/dotfiles/zsh/functions/hsyncworktrees" <<'EOF'
print -r -- "$*" >> "$HPREPARE_SYNC_TRACE"
EOF
cat > "$fixture/dotfiles/zsh/functions/htrimworkspaces" <<'EOF'
print -r -- "$*" >> "$HPREPARE_TRIM_TRACE"
print -r -- trim >> "$HPREPARE_ORDER_TRACE"
if [[ "${HPREPARE_TRIM_FAIL:-0}" == 1 ]]; then
  return 7
fi
EOF
cat > "$fixture/dotfiles/zsh/functions/_herdr_worktree_helpers" <<'EOF'
_h_repo_context() { return 0; }
_h_ensure_workspace() {
  print -r -- "$1" >> "$HPREPARE_ENSURE_TRACE"
  print -r -- ensure >> "$HPREPARE_ORDER_TRACE"
}
EOF
cat > "$fixture/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_TEST_COMMANDS"
state=$(cat "$HERDR_TEST_STATE" 2>/dev/null || true)

case "$*" in
  "status server --json")
    if [ "$state" = incompatible ]; then
      printf '%s\n' '{"status":"running","running":true,"compatible":false,"restart_needed":true}'
    else
      printf '%s\n' '{"status":"running","running":true,"compatible":true,"restart_needed":false}'
    fi
    ;;
  "session stop example")
    printf '%s\n' stopped > "$HERDR_TEST_STATE"
    ;;
  server)
    [ "$state" = stopped ] || exit 1
    printf '%s\n' running > "$HERDR_TEST_STATE"
    ;;
  "workspace list")
    [ -z "$state" ] || [ "$state" = running ]
    ;;
esac
EOF
chmod +x "$fixture/herdr"

: > "$fixture/herdr-commands"
export HERDR_TEST_COMMANDS="$fixture/herdr-commands"
export HERDR_TEST_STATE="$fixture/herdr-state"
export HPREPARE_SYNC_TRACE="$fixture/hprepare-sync.trace"
export HPREPARE_ENSURE_TRACE="$fixture/hprepare-ensure.trace"
export HPREPARE_TRIM_TRACE="$fixture/hprepare-trim.trace"
export HPREPARE_ORDER_TRACE="$fixture/hprepare-order.trace"
: > "$HPREPARE_SYNC_TRACE"
: > "$HPREPARE_ENSURE_TRACE"
: > "$HPREPARE_TRIM_TRACE"
: > "$HPREPARE_ORDER_TRACE"
run_hprepare() {
  source "$repo_root/zsh/functions/hprepare" "$@"
}

HOME="$fixture/home" \
USER=test \
HERDR_BIN="$fixture/herdr" \
HERDR_TEST_COMMANDS="$fixture/herdr-commands" \
HERDR_TEST_STATE="$fixture/herdr-state" \
RDEV_DOTFILES="$fixture/dotfiles" \
  run_hprepare example

session_plugins="$fixture/home/.config/herdr/sessions/example/plugins.json"
[[ -L "$session_plugins" ]]
[[ $(readlink "$session_plugins") == ../../plugins.json ]]
[[ $(<"$session_plugins") == '[]' ]]
[[ $(head -n 1 "$HPREPARE_SYNC_TRACE") == --prune-only ]]
[[ $(wc -l < "$HPREPARE_ENSURE_TRACE" | tr -d ' ') == 1 ]]
[[ $(head -n 1 "$HPREPARE_TRIM_TRACE") == --auto ]]
[[ "$(sed -n '1,2p' "$HPREPARE_ORDER_TRACE" | tr '\n' ' ')" == 'ensure trim ' ]]

# Trim is best-effort: an inspection failure warns but does not undo a
# successfully ensured target.
local trim_status
if HOME="$fixture/home" \
  USER=test \
  HERDR_BIN="$fixture/herdr" \
  HERDR_TEST_COMMANDS="$fixture/herdr-commands" \
  HERDR_TEST_STATE="$fixture/herdr-state" \
  RDEV_DOTFILES="$fixture/dotfiles" \
  HPREPARE_TRIM_FAIL=1 run_hprepare example; then
  trim_status=0
else
  trim_status=$?
fi
if (( trim_status != 0 )); then
  print -u2 -- "hprepare failed after trim failure (status $trim_status)"
  exit 1
fi
[[ $(wc -l < "$HPREPARE_ENSURE_TRACE" | tr -d ' ') == 2 ]]
[[ $(wc -l < "$HPREPARE_TRIM_TRACE" | tr -d ' ') == 2 ]]

# A sibling <repo>.git directory can be only a worktree container while the
# valid primary worktree remains at <repo>. Prefer the path Git recognizes.
split_path="$fixture/home/Developer/split"
mkdir -p "$fixture/home/Developer/split.git" "$split_path"
git -C "$split_path" init -q
HOME="$fixture/home" \
USER=test \
HERDR_BIN="$fixture/herdr" \
HERDR_TEST_COMMANDS="$fixture/herdr-commands" \
HERDR_TEST_STATE="$fixture/herdr-state" \
RDEV_DOTFILES="$fixture/dotfiles" \
  run_hprepare split
[[ "$PWD" == "${split_path:A}" ]]

print incompatible > "$fixture/herdr-state"
: > "$fixture/herdr-commands"
HOME="$fixture/home" \
USER=test \
HERDR_BIN="$fixture/herdr" \
HERDR_TEST_COMMANDS="$fixture/herdr-commands" \
HERDR_TEST_STATE="$fixture/herdr-state" \
HPREPARE_RESTART_INCOMPATIBLE=1 \
RDEV_DOTFILES="$fixture/dotfiles" \
  run_hprepare example

stop_line=$(grep -n '^session stop example$' "$fixture/herdr-commands" | cut -d: -f1)
start_line=$(grep -n '^server$' "$fixture/herdr-commands" | cut -d: -f1)
[[ -n "$stop_line" && -n "$start_line" ]]
(( stop_line < start_line ))
[[ $(<"$fixture/herdr-state") == running ]]

# hprepare needs the dotfiles path in nested helpers and child processes, but it
# must not leave that local-only path exported in the calling shell.
unset RDEV_DOTFILES
HOME="$fixture/home" \
USER=test \
HERDR_BIN="$fixture/herdr" \
HERDR_TEST_COMMANDS="$fixture/herdr-commands" \
HERDR_TEST_STATE="$fixture/herdr-state" \
  run_hprepare example
(( ! ${+RDEV_DOTFILES} ))

print 'hprepare tests passed'
