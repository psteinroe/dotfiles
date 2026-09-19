#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/dotfiles/zsh/functions" "$fixture/repo.git/main" "$fixture/repo.git/feature" "$fixture/bin"

cat > "$fixture/dotfiles/zsh/functions/_herdr_worktree_helpers" <<'EOF'
_h_require_herdr() { return 0; }
_h_repo_context() { typeset -g H_WORKTREE_ROOT="$PWD"; }
_h_git_worktree_paths() { print "$PWD/main"; print "$PWD/feature"; }
_h_worktree_label() { print "${1:t}"; }
_h_ensure_workspace() { print "ensure $1 $2 $3" >> "$HSYNC_TRACE"; }
_h_prune_missing_workspaces() { print prune >> "$HSYNC_TRACE"; }
EOF
cat > "$fixture/bin/herdr" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$fixture/bin/herdr"

run_sync() {
  : > "$fixture/trace"
  (
    cd "$fixture/repo.git"
    PATH="$fixture/bin:$PATH" RDEV_DOTFILES="$fixture/dotfiles" \
      HSYNC_TRACE="$fixture/trace" source "$repo_root/zsh/functions/hsyncworktrees" "$@"
  )
}

run_sync --prune-only
[[ $(<"$fixture/trace") == prune ]]

run_sync
[[ $(grep -c '^ensure ' "$fixture/trace") == 2 ]]
! grep -q '^prune$' "$fixture/trace"

run_sync --prune
[[ $(grep -c '^ensure ' "$fixture/trace") == 2 ]]
grep -q '^prune$' "$fixture/trace"

if run_sync --bad >/dev/null 2>&1; then
  print -u2 -- 'hsyncworktrees accepted an invalid mode'
  exit 1
fi

print 'hsyncworktrees tests passed'
