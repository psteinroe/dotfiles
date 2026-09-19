#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/dotfiles/zsh/functions" "$fixture/repo"
git -C "$fixture/repo" init -q -b main
git -C "$fixture/repo" config user.email test@example.com
git -C "$fixture/repo" config user.name Test
print test > "$fixture/repo/file"
git -C "$fixture/repo" add file
git -C "$fixture/repo" commit -qm init

cat > "$fixture/dotfiles/zsh/functions/htrimworkspaces" <<'EOF'
print -r -- "$*" >> "$HWTCREATE_TRIM_TRACE"
print -r -- trim >> "$HWTCREATE_ORDER_TRACE"
if [[ "${HWTCREATE_TRIM_FAIL:-0}" == 1 ]]; then
  return 9
fi
EOF
cat > "$fixture/dotfiles/zsh/functions/_herdr_worktree_helpers" <<'EOF'
_h_require_herdr() { return 0; }
_h_repo_context() {
  typeset -g H_WORKTREE_ROOT="${PWD:h}"
}
_h_worktree_label() {
  print -r -- "${1:t}"
}
_h_ensure_workspace() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$HWTCREATE_TEST_RESULT"
  print -r -- ensure >> "$HWTCREATE_ORDER_TRACE"
}
EOF

run_hwtcreate() {
  (
    cd "$fixture/repo"
    RDEV_DOTFILES="$fixture/dotfiles" \
    HWTCREATE_TEST_RESULT="$fixture/result" \
    HWTCREATE_TRIM_TRACE="$fixture/trim.trace" \
    HWTCREATE_ORDER_TRACE="$fixture/order.trace" \
      source "$repo_root/zsh/functions/hwtcreate" "$@"
  )
}

run_hwtcreate main
IFS=$'\t' read -r wt_path label focus < "$fixture/result"
[[ "$wt_path" == "$fixture/repo" ]]
[[ "$label" == repo ]]
[[ "$focus" == 1 ]]
[[ $(head -n 1 "$fixture/trim.trace") == --auto ]]
[[ "$(sed -n '1,2p' "$fixture/order.trace" | tr '\n' ' ')" == 'ensure trim ' ]]

# Trim failures are warnings only; the target was already ensured successfully.
HWTCREATE_TRIM_FAIL=1 run_hwtcreate main >/dev/null 2>&1
IFS=$'\t' read -r wt_path label focus < "$fixture/result"
[[ "$wt_path" == "$fixture/repo" ]]

trim_count_before=$(wc -l < "$fixture/trim.trace" | tr -d ' ')
run_hwtcreate --no-focus main
IFS=$'\t' read -r wt_path label focus < "$fixture/result"
[[ "$focus" == 0 ]]
# Background preparation must not immediately auto-close its own idle workspace.
[[ $(wc -l < "$fixture/trim.trace" | tr -d ' ') == "$trim_count_before" ]]

run_hwtcreate --focus main
IFS=$'\t' read -r wt_path label focus < "$fixture/result"
[[ "$focus" == 1 ]]
[[ $(wc -l < "$fixture/trim.trace" | tr -d ' ') == $((trim_count_before + 1)) ]]

if run_hwtcreate --no-focus >/dev/null 2>&1; then
  print -u2 -- "hwtcreate accepted a missing branch"
  exit 1
fi

# The Shift+G create overlay must not close itself when hwtcreate fails. Closing
# immediately hides the useful Git/setup error and makes the overlay look like
# it crashed after Enter.
manager_fixture="$fixture/manager"
mkdir -p "$manager_fixture/repo" "$manager_fixture/dotfiles/zsh/functions" "$manager_fixture/bin"
git -C "$manager_fixture/repo" init -q -b main
cat > "$manager_fixture/dotfiles/zsh/functions/_herdr_worktree_helpers" <<'EOF'
_h_repo_context() {
  typeset -g H_REPO_ROOT="$PWD"
  typeset -g H_REPO_NAME=repo
  typeset -g H_WORKTREE_ROOT="${PWD:h}/repo.git"
}
EOF
cat > "$manager_fixture/dotfiles/zsh/functions/hwtcreate" <<'EOF'
print -u2 -- 'simulated worktree creation failure'
return 42
EOF
cat > "$manager_fixture/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_TRACE"
EOF
chmod +x "$manager_fixture/bin/herdr"
: > "$manager_fixture/herdr.trace"

set +e
printf 'new-branch\n\n' | env \
  PATH="$manager_fixture/bin:$PATH" \
  RDEV_DOTFILES="$manager_fixture/dotfiles" \
  HWS_MODE=create \
  HWS_PROJECT_CWD="$manager_fixture/repo" \
  HERDR_PANE_ID=manager-overlay \
  HERDR_TRACE="$manager_fixture/herdr.trace" \
  zsh "$repo_root/herdr/plugins/worktree-sync/manager.sh" \
  > "$manager_fixture/output" 2>&1
manager_status=$?
set -e

[[ "$manager_status" == 42 ]] || {
  print -u2 -- "failed create overlay returned $manager_status instead of 42"
  exit 1
}
grep -q 'simulated worktree creation failure' "$manager_fixture/output"
grep -q 'Worktree creation failed' "$manager_fixture/output" || {
  print -u2 -- 'failed create overlay did not explain that creation failed'
  exit 1
}
if grep -q '^pane close manager-overlay$' "$manager_fixture/herdr.trace"; then
  print -u2 -- 'failed create overlay closed itself immediately'
  exit 1
fi

print 'hwtcreate tests passed'
