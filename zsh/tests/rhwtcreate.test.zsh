#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

export RDEV_HOST=fixture-host RDEV_REMOTE_USER=test RDEV_HOME=/home/test
export RDEV_REMOTE_DOTFILES="$repo_root"
export RHWT_TRACE="$fixture/trace"
: > "$RHWT_TRACE"
fpath=("$repo_root/zsh/functions" $fpath)
autoload -Uz rhwtcreate
rdev_calls=0
HEALTH_MODE=healthy
FINAL_RC=0

rdev() {
  (( ++rdev_calls ))
  print -r -- "rdev $*" >> "$RHWT_TRACE"
  return "${RDEV_RC:-0}"
}
rherdr() {
  print -u2 -- 'rherdr must not be used by rhwtcreate'
  return 1
}
ssh() {
  local command=${@[-1]}
  print -r -- "$command" >> "$RHWT_TRACE"
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
: > "$RHWT_TRACE"
rdev_calls=0 HEALTH_MODE=healthy FINAL_RC=0
rhwtcreate hellomateo feature/test
(( rdev_calls == 0 ))
[[ $(grep -c 'workspace list' "$RHWT_TRACE") == 1 ]]
[[ $(grep -c '^' "$RHWT_TRACE") == 2 ]]

# An absent/stale session invokes rdev, then runs the normal final command.
: > "$RHWT_TRACE"
rdev_calls=0 HEALTH_MODE=absent FINAL_RC=0
rhwtcreate hellomateo feature/test
(( rdev_calls == 1 ))
[[ $(grep -c '^' "$RHWT_TRACE") == 3 ]]

# Preparation failures propagate and prevent the final remote command.
rdev_calls=0 HEALTH_MODE=absent RDEV_RC=23
if rhwtcreate hellomateo feature/test; then
  print -u2 -- 'rdev failure unexpectedly succeeded'
  exit 1
else
  [[ $? == 23 ]]
fi
unset RDEV_RC

# SSH transport failure is distinct and never calls rdev.
rdev_calls=0 HEALTH_MODE=transport
if rhwtcreate hellomateo feature/test; then
  print -u2 -- 'transport failure unexpectedly succeeded'
  exit 1
else
  [[ $? == 255 ]]
fi
(( rdev_calls == 0 ))

# A failure from the final worktree command remains its own failure.
: > "$RHWT_TRACE"
rdev_calls=0 HEALTH_MODE=healthy FINAL_RC=19
if rhwtcreate hellomateo feature/test; then
  print -u2 -- 'final command failure unexpectedly succeeded'
  exit 1
else
  [[ $? == 19 ]]
fi
(( rdev_calls == 0 ))
! grep -q 'rherdr' "$RHWT_TRACE"

print 'rhwtcreate health tests passed'
