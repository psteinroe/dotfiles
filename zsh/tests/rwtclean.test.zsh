#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}

typeset -g RWT_CLEAN_RUNNER=""
ssh() {
  typeset -g RWT_CLEAN_RUNNER=${@[-1]}
}

remote_command() {
  local assignment=${RWT_CLEAN_RUNNER%%; cmd=*}
  local encoded=${(Q)${assignment#encoded=}}
  printf '%s' "$encoded" | base64 -d
}

fpath=("$repo_root/zsh/functions" $fpath)
autoload -Uz rwtclean
export LOCAL_DOTFILES="$repo_root"
export RDEV_HOST=fixture-host RDEV_REMOTE_USER=test RDEV_HOME=/home/test
export RDEV_REMOTE_DOTFILES=/home/test/Developer/dotfiles

# A custom stale threshold must cross the SSH boundary into wtclean.
WTCLEAN_STALE_DAYS=30 rwtclean example
command=$(remote_command)
[[ "$command" == *"export WTCLEAN_STALE_DAYS=30;"* ]]
[[ "$command" == *"source /home/test/Developer/dotfiles/zsh/functions/wtclean"* ]]

# Leaving the threshold unset preserves wtclean's own seven-day default.
unset WTCLEAN_STALE_DAYS
rwtclean example
command=$(remote_command)
[[ "$command" != *"export WTCLEAN_STALE_DAYS="* ]]

print 'rwtclean environment forwarding tests passed'
