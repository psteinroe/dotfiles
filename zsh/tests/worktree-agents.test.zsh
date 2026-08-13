#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
launcher="$repo_root/agents/pi/skills/worktree-agents/scripts/worktree-agent.zsh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin" "$fixture/dotfiles/zsh/functions" "$fixture/repo"
git -C "$fixture/repo" init -q
git -C "$fixture/repo" config user.email test@example.com
git -C "$fixture/repo" config user.name Test
print test > "$fixture/repo/file"
git -C "$fixture/repo" add file
git -C "$fixture/repo" commit -qm init

cat > "$fixture/dotfiles/zsh/functions/hwtcreate" <<'EOF'
print -r -- "$*" > "$HERDR_TEST_HWTCREATE_ARGS"
[[ "$1" == --no-focus ]] || return 1
shift
typeset -g WTENSURE_WORKTREE_PATH="$HERDR_TEST_WORKTREE"
typeset -g WTENSURE_WORKTREE_NAME="$1"
cd "$WTENSURE_WORKTREE_PATH" || return
_h_workspace_id_for_path_or_label() {
  print -r -- w2
}
touch "$HERDR_TEST_CREATED"
EOF

cat > "$fixture/bin/herdr" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$HERDR_TEST_TRACE"

case "$1 $2" in
  "workspace get")
    printf '%s\n' '{"result":{"workspace":{"workspace_id":"'$3'"}}}'
    ;;
  "workspace list")
    if [ "${HERDR_TEST_EXISTING:-0}" = 1 ] || [ -e "$HERDR_TEST_CREATED" ]; then
      printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1"},{"workspace_id":"w2"}]}}'
    else
      printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1"}]}}'
    fi
    ;;
  "workspace focus")
    printf '%s\n' '{}'
    ;;
  "pane list")
    printf '%s\n' '{"result":{"panes":[{"pane_id":"w2:p1","cwd":"'"$HERDR_TEST_WORKTREE"'","foreground_cwd":"'"$HERDR_TEST_WORKTREE"'"}]}}'
    ;;
  "tab create")
    printf '%s\n' '{"result":{"tab":{"tab_id":"w2:t2"},"root_pane":{"pane_id":"w2:p2"}}}'
    ;;
  "tab close")
    printf '%s\n' '{}'
    ;;
  "agent list")
    if [ "${HERDR_TEST_NAME_COLLISION:-0}" = 1 ]; then
      printf '%s\n' '{"result":{"agents":[{"agent":"wt-feature"}]}}'
    else
      printf '%s\n' '{"result":{"agents":[]}}'
    fi
    ;;
  "agent start"|"agent prompt"|"agent focus")
    printf '%s\n' '{}'
    ;;
  *)
    printf 'unexpected herdr command: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fixture/bin/herdr"

run_launcher() {
  local existing="$1"
  local collision="$2"
  shift 2
  rm -f "$fixture/created"
  : > "$fixture/herdr.trace"
  (
    cd "$fixture/repo"
    PATH="$fixture/bin:$PATH" \
    HERDR_ENV=1 \
    HERDR_WORKSPACE_ID=w1 \
    HERDR_TEST_EXISTING="$existing" \
    HERDR_TEST_NAME_COLLISION="$collision" \
    HERDR_TEST_CREATED="$fixture/created" \
    HERDR_TEST_TRACE="$fixture/herdr.trace" \
    HERDR_TEST_HWTCREATE_ARGS="$fixture/hwtcreate.args" \
    HERDR_TEST_WORKTREE="$fixture/repo" \
    RDEV_DOTFILES="$fixture/dotfiles" \
      "$launcher" "$@"
  )
}

ensure_json=$(run_launcher 0 0 ensure feature)
[[ "$(print -r -- "$ensure_json" | jq -r .workspace_id)" == w2 ]]
[[ "$(print -r -- "$ensure_json" | jq -r .created_workspace)" == true ]]
[[ "$(<"$fixture/hwtcreate.args")" == "--no-focus feature" ]]
if grep -q '^workspace focus ' "$fixture/herdr.trace"; then
  print -u2 -- "ensure unexpectedly focused the workspace"
  exit 1
fi

run_launcher 0 0 ensure feature --focus >/dev/null
grep -q '^workspace focus w2$' "$fixture/herdr.trace"

launch_json=$(run_launcher 0 0 launch feature --name reviewer --prompt 'Review the change')
[[ "$(print -r -- "$launch_json" | jq -r .pane_id)" == 'w2:p1' ]]
[[ "$(print -r -- "$launch_json" | jq -r .agent_name)" == reviewer ]]
grep -q '^agent start reviewer --kind pi --pane w2:p1$' "$fixture/herdr.trace"
grep -q '^agent prompt reviewer Review the change$' "$fixture/herdr.trace"
if grep -q '^tab create ' "$fixture/herdr.trace"; then
  print -u2 -- "fresh workspace unexpectedly created another tab"
  exit 1
fi

launch_json=$(run_launcher 1 1 launch feature --prompt 'Implement it')
[[ "$(print -r -- "$launch_json" | jq -r .created_workspace)" == false ]]
[[ "$(print -r -- "$launch_json" | jq -r .tab_id)" == 'w2:t2' ]]
[[ "$(print -r -- "$launch_json" | jq -r .pane_id)" == 'w2:p2' ]]
[[ "$(print -r -- "$launch_json" | jq -r .agent_name)" == 'wt-feature-2' ]]
grep -q '^tab create --workspace w2 --cwd .* --label wt-feature-2 --no-focus$' "$fixture/herdr.trace"
grep -q '^agent start wt-feature-2 --kind pi --pane w2:p2$' "$fixture/herdr.trace"

print 'worktree-agents tests passed'
