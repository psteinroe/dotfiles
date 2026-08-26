#!/usr/bin/env zsh
set -euo pipefail
setopt typesetsilent

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
fixture=${fixture:A}
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/seed" "$fixture/dotfiles/zsh/functions" "$fixture/home/.local/bin"
git -C "$fixture/seed" init -q -b main
git -C "$fixture/seed" config user.email test@example.com
git -C "$fixture/seed" config user.name Test
print base > "$fixture/seed/file"
git -C "$fixture/seed" add file
git -C "$fixture/seed" commit -qm init

git init --bare -q "$fixture/origin.git"
git -C "$fixture/seed" remote add origin "$fixture/origin.git"
git -C "$fixture/seed" push -q origin main
git --git-dir="$fixture/origin.git" symbolic-ref HEAD refs/heads/main

git clone --bare -q "$fixture/origin.git" "$fixture/repo.git"
git -C "$fixture/repo.git" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

# Reproduce ce-platform: the clone remembers origin/HEAD -> origin/main, then
# the remote changes its default to dev and deletes main. The older Git on rdev
# prunes origin/main but leaves the local origin/HEAD symbolic ref stale.
git -C "$fixture/seed" branch dev
git -C "$fixture/seed" push -q origin dev
git --git-dir="$fixture/origin.git" symbolic-ref HEAD refs/heads/dev
git --git-dir="$fixture/origin.git" update-ref -d refs/heads/main
git -C "$fixture/repo.git" fetch -q --prune origin
git --git-dir="$fixture/repo.git" worktree add -q -b dev "$fixture/repo.git/dev" origin/dev
git -C "$fixture/repo.git" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
! git -C "$fixture/repo.git" show-ref --verify --quiet refs/remotes/origin/main

# Preserve the stale symref after wtensure's fetch, matching the older Git on
# rdev. Newer local Git versions repair origin/HEAD during fetch automatically.
real_git=$(command -v git)
cat > "$fixture/home/.local/bin/git" <<EOF
#!/bin/sh
if [ "\$1 \$2 \$3" = "fetch origin --prune" ]; then
  "$real_git" "\$@" || exit
  "$real_git" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  exit
fi
exec "$real_git" "\$@"
EOF
chmod +x "$fixture/home/.local/bin/git"
ln -s "$repo_root/zsh/functions/gh-default-branch" \
  "$fixture/dotfiles/zsh/functions/gh-default-branch"
print -r -- ':' > "$fixture/dotfiles/zsh/functions/wtsetup"
print -r -- ':' > "$fixture/dotfiles/zsh/functions/wtcheckout"

(
  cd "$fixture/repo.git/dev"
  HOME="$fixture/home" RDEV_DOTFILES="$fixture/dotfiles" \
    source "$repo_root/zsh/functions/wtensure" feature/new-worktree
  [[ "$WTENSURE_WORKTREE_PATH" == "$fixture/repo.git/feature-new-worktree" ]]
  [[ "$(git branch --show-current)" == feature/new-worktree ]]
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/dev)" ]]
)

print 'wtensure tests passed'
