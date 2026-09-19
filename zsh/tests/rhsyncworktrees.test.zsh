#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

export RDEV_HOST=fixture-host RDEV_REMOTE_USER=test RDEV_HOME=/home/test
export RDEV_REMOTE_DOTFILES="$repo_root"
export RHSYNC_TRACE="$fixture/trace"
: > "$RHSYNC_TRACE"
fpath=("$repo_root/zsh/functions" $fpath)
autoload -Uz rhsyncworktrees
rdev_calls=0
HEALTH_MODE=healthy
FINAL_RC=0

rdev() {
  (( ++rdev_calls ))
  print -r -- "rdev $*" >> "$RHSYNC_TRACE"
  return "${RDEV_RC:-0}"
}
rherdr() {
  print -u2 -- 'rherdr must not be used by rhsyncworktrees'
  return 1
}
ssh() {
  local command=${@[-1]}
  print -r -- "$command" >> "$RHSYNC_TRACE"
  if [[ "$command" == *'workspace list'* ]]; then
    case "$HEALTH_MODE" in
      healthy) return 0 ;;
      transport) return 255 ;;
      *) return 1 ;;
    esac
  fi
  return "${FINAL_RC:-0}"
}

# A live healthy session does not invoke rdev.
: > "$RHSYNC_TRACE"
rdev_calls=0 HEALTH_MODE=healthy FINAL_RC=0
rhsyncworktrees hellomateo --prune
(( rdev_calls == 0 ))
[[ $(grep -c 'workspace list' "$RHSYNC_TRACE") == 1 ]]
[[ $(grep -c '^' "$RHSYNC_TRACE") == 2 ]]

# An absent/stale session invokes rdev, then runs the normal final command.
: > "$RHSYNC_TRACE"
rdev_calls=0 HEALTH_MODE=absent FINAL_RC=0
rhsyncworktrees hellomateo --prune
(( rdev_calls == 1 ))
[[ $(grep -c '^' "$RHSYNC_TRACE") == 3 ]]

# Preparation failures propagate and prevent the final remote command.
rdev_calls=0 HEALTH_MODE=absent RDEV_RC=23
if rhsyncworktrees hellomateo --prune; then
  print -u2 -- 'rdev failure unexpectedly succeeded'
  exit 1
else
  [[ $? == 23 ]]
fi
unset RDEV_RC

# SSH transport failure is distinct and never calls rdev.
rdev_calls=0 HEALTH_MODE=transport
if rhsyncworktrees hellomateo --prune; then
  print -u2 -- 'transport failure unexpectedly succeeded'
  exit 1
else
  [[ $? == 255 ]]
fi
(( rdev_calls == 0 ))

# A failure from the final sync command remains its own failure.
: > "$RHSYNC_TRACE"
rdev_calls=0 HEALTH_MODE=healthy FINAL_RC=19
if rhsyncworktrees hellomateo --prune; then
  print -u2 -- 'final command failure unexpectedly succeeded'
  exit 1
else
  [[ $? == 19 ]]
fi
(( rdev_calls == 0 ))
! grep -q 'rherdr' "$RHSYNC_TRACE"

print 'rhsyncworktrees health tests passed'
