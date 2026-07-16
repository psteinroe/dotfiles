#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

git init --bare -q "$fixture/origin.git"
git clone -q "$fixture/origin.git" "$fixture/source"
git -C "$fixture/source" config user.email test@example.com
git -C "$fixture/source" config user.name Test
mkdir -p "$fixture/source/zsh/functions"
print -r -- 'base' > "$fixture/source/state.txt"
print -r -- ': > "$DOTFILES_DIR/.rebuilt"' > "$fixture/source/zsh/functions/rebuild"
git -C "$fixture/source" add .
git -C "$fixture/source" commit -qm base
git -C "$fixture/source" branch -M main
git -C "$fixture/source" push -qu origin main
git --git-dir="$fixture/origin.git" symbolic-ref HEAD refs/heads/main

git clone -q "$fixture/origin.git" "$fixture/remote"
git -C "$fixture/remote" config user.email test@example.com
git -C "$fixture/remote" config user.name Test
print -r -- 'remote-only' > "$fixture/remote/state.txt"
git -C "$fixture/remote" commit -qam remote-only

print -r -- 'upstream' > "$fixture/source/state.txt"
git -C "$fixture/source" commit -qam upstream
git -C "$fixture/source" push -q origin main

# Leave the deployment checkout in the exact state that makes `git pull` fail.
git -C "$fixture/remote" pull --no-rebase >/dev/null 2>&1 || true
[[ -n $(git -C "$fixture/remote" diff --name-only --diff-filter=U) ]]
mkdir "$fixture/remote/untracked"
print -r -- 'discard me' > "$fixture/remote/untracked/file.txt"

ssh() {
  local runner=${@[-1]}
  local assignment=${runner%%; cmd=*}
  local encoded=${(Q)${assignment#encoded=}}
  local command=$(printf '%s' "$encoded" | base64 -d)
  HOME="$fixture/home" zsh -c "$command"
}

fpath=("$repo_root/zsh/functions" $fpath)
autoload -Uz rrebuild
RDEV_REMOTE_USER=test \
  RDEV_HOME="$fixture/home" \
  RDEV_DOTFILES="$fixture/remote" \
  rrebuild fixture-host

[[ -z $(git -C "$fixture/remote" diff --name-only --diff-filter=U) ]]
[[ $(git -C "$fixture/remote" rev-parse HEAD) == $(git -C "$fixture/remote" rev-parse '@{upstream}') ]]
[[ $(<"$fixture/remote/state.txt") == upstream ]]
[[ ! -e "$fixture/remote/untracked" ]]
[[ -f "$fixture/remote/.rebuilt" ]]

print 'rrebuild force-sync test passed'
