#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/dotfiles/zsh/functions" "$fixture/repo.git/idle" "$fixture/bin" "$fixture/state"

cat > "$fixture/dotfiles/zsh/functions/_herdr_worktree_helpers" <<'EOF'
_h_require_herdr() { herdr workspace list >/dev/null; }
_h_repo_context() { typeset -g H_WORKTREE_ROOT="$PWD"; }
_h_git_worktree_paths() { print "$PWD/idle"; }
_h_workspace_rows() { printf 'candidate-id\t%s\tidle\n' "$PWD/idle"; }
EOF
cat > "$fixture/bin/herdr" <<'EOF'
#!/bin/sh
set -eu
kind="$1-$2"
count_file="$HTRIM_STATE/$kind.count"
n=0
[ -f "$count_file" ] && n=$(cat "$count_file")
n=$((n + 1))
printf '%s\n' "$n" > "$count_file"
case "$kind" in
  workspace-list)
    focused=false
    [ "$HTRIM_MODE" = focus-change ] && [ "$n" -ge 4 ] && focused=true
    printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"candidate-id","label":"idle","focused":'"$focused"'}]}}'
    ;;
  pane-list)
    if [ "$HTRIM_MODE" = agent-change ] && [ "$n" -ge 2 ]; then
      printf '%s\n' '{"result":{"panes":[{"pane_id":"candidate-pane","agent":"pi"}]}}'
    else
      printf '%s\n' '{"result":{"panes":[{"pane_id":"candidate-pane"}]}}'
    fi
    ;;
  pane-process-info)
    shell_pid=500
    [ "$HTRIM_MODE" = background ] && shell_pid=501
    [ "$HTRIM_MODE" = ps-failure ] && shell_pid=502
    if [ "$HTRIM_MODE" = process-change ] && [ "$n" -ge 2 ]; then
      printf '%s\n' '{"result":{"process_info":{"shell_pid":500,"foreground_processes":[{"pid":999}]}}}'
    else
      printf '%s\n' '{"result":{"process_info":{"shell_pid":'"$shell_pid"',"foreground_processes":[{"pid":'"$shell_pid"'}]}}}'
    fi
    ;;
  workspace-close)
    printf '%s\n' "$3" >> "$HTRIM_CLOSES"
    ;;
  *) exit 2 ;;
esac
EOF
cat > "$fixture/bin/ps" <<'EOF'
#!/bin/sh
set -eu
n=0
[ -f "$HTRIM_STATE/ps.count" ] && n=$(cat "$HTRIM_STATE/ps.count")
printf '%s\n' "$((n + 1))" > "$HTRIM_STATE/ps.count"
[ "$HTRIM_MODE" = ps-failure ] && [ "$n" -ge 2 ] && exit 1
case "$HTRIM_MODE" in
  background) printf '501 1\n601 501\n' ;;
  ps-failure) printf '502 1\n' ;;
  *) printf '500 1\n' ;;
esac
EOF
chmod +x "$fixture/bin/herdr" "$fixture/bin/ps"
: > "$fixture/closes"

run_trim() {
  find "$fixture/state" -type f -name '*.count' -delete
  : > "$fixture/closes"
  (
    cd "$fixture/repo.git"
    export PATH="$fixture/bin:$PATH" RDEV_DOTFILES="$fixture/dotfiles" \
      HTRIM_STATE="$fixture/state" HTRIM_CLOSES="$fixture/closes" HTRIM_MODE="$1"
    if [ "$#" -gt 1 ]; then
      set -- "$2"
    else
      set --
    fi
    source "$repo_root/zsh/functions/htrimworkspaces" "$@"
  )
}

# A descendant of the pane shell protects the workspace.
background=$(run_trim background)
[[ "$background" == *'0 candidate(s)'* ]]
[[ "$background" == *'background or descendant process'* ]]
[[ ! -s "$fixture/closes" ]]

# A failed process-table read is uncertain and protects the workspace.
process_failure=$(run_trim ps-failure --apply <<< 'y')
[[ "$process_failure" == *'SKIP candidate-id (idle)'* ]]
[[ "$process_failure" == *'process-table inspection failed or shell PID is absent'* ]]
[[ ! -s "$fixture/closes" ]]

# State changes after preview are caught by the first post-confirmation refresh.
for mode in focus-change agent-change process-change; do
  changed=$(run_trim "$mode" --apply <<< 'y')
  [[ "$changed" == *'1 candidate(s)'* ]]
  [[ "$changed" == *"SKIP candidate-id (idle)"* ]]
  [[ ! -s "$fixture/closes" ]]
done

# A clean second inspection is required, and the close follows three fresh
# process inspections: preview, immediately after confirmation, and pre-close.
clean=$(run_trim clean --apply <<< 'y')
[[ "$clean" == *'Closed Herdr workspace: candidate-id'* ]]
[[ "$(cat "$fixture/state/pane-process-info.count")" == 3 ]]
[[ "$(cat "$fixture/state/ps.count")" == 3 ]]
[[ "$(cat "$fixture/state/workspace-list.count")" == 5 ]] # require + preview + 3 validations
[[ "$(cat "$fixture/closes")" == candidate-id ]]

# --auto never reads input, but uses the same preview, group refresh, and
# immediate pre-close refresh sequence as --apply.
auto_clean=$(run_trim clean --auto)
[[ "$auto_clean" == *'Closed Herdr workspace: candidate-id'* ]]
[[ "$auto_clean" == *'--auto: closed 1, skipped 0'* ]]
[[ "$(cat "$fixture/state/pane-process-info.count")" == 3 ]]
[[ "$(cat "$fixture/state/ps.count")" == 3 ]]
[[ "$(cat "$fixture/state/workspace-list.count")" == 5 ]]
[[ "$(cat "$fixture/closes")" == candidate-id ]]

# Automatic cleanup also skips a sibling that becomes active/uncertain after
# its clean preview, without waiting for confirmation input.
for mode in focus-change agent-change process-change; do
  auto_changed=$(run_trim "$mode" --auto)
  [[ "$auto_changed" == *'SKIP candidate-id (idle)'* ]]
  [[ "$auto_changed" == *'--auto: closed 0, skipped 1'* ]]
  [[ ! -s "$fixture/closes" ]]
done

print 'htrimworkspaces tests passed'
