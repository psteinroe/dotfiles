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
}
EOF

run_hwtcreate() {
  (
    cd "$fixture/repo"
    RDEV_DOTFILES="$fixture/dotfiles" \
    HWTCREATE_TEST_RESULT="$fixture/result" \
      source "$repo_root/zsh/functions/hwtcreate" "$@"
  )
}

run_hwtcreate main
IFS=$'\t' read -r wt_path label focus < "$fixture/result"
[[ "$wt_path" == "$fixture/repo" ]]
[[ "$label" == repo ]]
[[ "$focus" == 1 ]]

run_hwtcreate --no-focus main
IFS=$'\t' read -r wt_path label focus < "$fixture/result"
[[ "$focus" == 0 ]]

run_hwtcreate --focus main
IFS=$'\t' read -r wt_path label focus < "$fixture/result"
[[ "$focus" == 1 ]]

if run_hwtcreate --no-focus >/dev/null 2>&1; then
  print -u2 -- "hwtcreate accepted a missing branch"
  exit 1
fi

print 'hwtcreate tests passed'
