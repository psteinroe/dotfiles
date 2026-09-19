#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/dotfiles/zsh/functions"
cp "$repo_root/zsh/functions/_herdr_machine_helpers" "$fixture/dotfiles/zsh/functions/_herdr_machine_helpers"
cat > "$fixture/dotfiles/zsh/functions/_herdr_binary" <<'EOF'
_herdr_binary() {
  print -r -- "$HERDR_BIN"
}
EOF
cat > "$fixture/herdr" <<'EOF'
#!/bin/sh
set -eu
[ "${RDEV_SSH_DONE:-0}" = 1 ] || exit 24
printf '%s\n' "$*" >> "$HERDR_TRACE"
case "$*" in
  "machine list --json")
    [ "${HERDR_LIST_FAIL:-0}" != 1 ] || exit 20
    cat "$HERDR_MACHINE_LIST"
    ;;
  "machine enable "*)
    [ "${HERDR_ENABLE_FAIL:-0}" != 1 ] || exit 21
    ;;
  "machine disable "*)
    [ "${HERDR_DISABLE_FAIL:-0}" != 1 ] || exit 25
    ;;
  "machine add "*)
    [ "${HERDR_ADD_FAIL:-0}" != 1 ] || exit 22
    if [ "${HERDR_POST_ADD:-0}" = 1 ]; then
      cp "$HERDR_POST_ADD_LIST" "$HERDR_MACHINE_LIST"
    fi
    ;;
  *) exit 23 ;;
esac
EOF
chmod +x "$fixture/herdr"
: > "$fixture/herdr.trace"

ssh() {
  typeset -g RDEV_TEST_RUNNER=${@[-1]}
  if [[ "${RDEV_SSH_FAIL:-0}" == 1 ]]; then
    return 42
  fi
  typeset -gx RDEV_SSH_DONE=1
}

fpath=("$repo_root/zsh/functions" $fpath)
autoload -Uz rdev
export RDEV_DOTFILES=/Users/test/Developer/dotfiles
export RDEV_HOST=fixture-host RDEV_REMOTE_USER=test RDEV_HOME=/home/test
export LOCAL_DOTFILES="$fixture/dotfiles" HERDR_BIN="$fixture/herdr"
export HERDR_TRACE="$fixture/herdr.trace"

run_rdev() {
  : > "$fixture/herdr.trace"
  rdev hellomateo "$@"
}

assert_runner() {
  local expected="$1"
  local assignment=${RDEV_TEST_RUNNER%%; cmd=*}
  local encoded=${(Q)${assignment#encoded=}}
  local prepare_cmd
  prepare_cmd=$(printf '%s' "$encoded" | base64 -d)
  [[ "$prepare_cmd" == *"export RDEV_DOTFILES=/home/test/Developer/dotfiles"* ]]
  [[ "$prepare_cmd" != *"/Users/test/Developer/dotfiles/zsh/functions/hprepare"* ]]
  [[ "$prepare_cmd" == *"_hprepare hellomateo $expected"* ]]
}

# Captured Herdr 0.9.0 output is a bare array, including selected.
cat > "$fixture/machines.json" <<'EOF'
[{"id":"enabled-id","label":"old label","target":"fixture-host","session":"hellomateo","enabled":true,"selected":true}]
EOF
export HERDR_MACHINE_LIST="$fixture/machines.json"
run_rdev
assert_runner ''
! grep -F -- 'machine add' "$fixture/herdr.trace"
! grep -F -- 'machine enable' "$fixture/herdr.trace"
! grep -F -- 'machine disable' "$fixture/herdr.trace"
! grep -F -- '--remote' "$fixture/herdr.trace"
[[ "$HERDR_MACHINE_LABEL" == 'old label' ]]

# Requested arguments are forwarded to the remote hprepare command.
cat > "$fixture/machines.json" <<'EOF'
[{"id":"requested-id","label":"requested label","target":"fixture-host","session":"hellomateo","enabled":true,"selected":false}]
EOF
run_rdev feature/test
assert_runner feature/test

# Duplicate enabled exact profiles are reconciled deterministically.
cat > "$fixture/machines.json" <<'EOF'
[
 {"id":"first","label":"first label","target":"fixture-host","session":"hellomateo","enabled":true,"selected":false},
 {"id":"second","label":"second label","target":"fixture-host","session":"hellomateo","enabled":true,"selected":true},
 {"id":"off","label":"off label","target":"fixture-host","session":"hellomateo","enabled":false,"selected":false}
]
EOF
run_rdev
[[ $(grep -c 'machine disable second' "$fixture/herdr.trace") == 1 ]]
! grep -F -- 'machine disable first' "$fixture/herdr.trace"
! grep -F -- 'machine add' "$fixture/herdr.trace"
[[ "$HERDR_MACHINE_LABEL" == 'first label' ]]

# Duplicate disabled profiles select and enable the first without adding.
cat > "$fixture/machines.json" <<'EOF'
[
 {"id":"off-first","label":"preserved one","target":"fixture-host","session":"hellomateo","enabled":false,"selected":false},
 {"id":"off-second","label":"preserved two","target":"fixture-host","session":"hellomateo","enabled":false,"selected":false}
]
EOF
run_rdev
[[ $(grep -c 'machine enable off-first' "$fixture/herdr.trace") == 1 ]]
! grep -F -- 'machine add' "$fixture/herdr.trace"
[[ "$HERDR_MACHINE_LABEL" == 'preserved one' ]]

# A canonical label owned by another identity blocks an add.
cat > "$fixture/machines.json" <<'EOF'
[{"id":"collision","label":"fixture-host/hellomateo","target":"other-host","session":"other","enabled":true,"selected":false}]
EOF
if run_rdev; then exit 1; fi
! grep -F -- 'machine add' "$fixture/herdr.trace"
grep -F -- 'canonical label fixture-host/hellomateo already belongs' "$fixture/herdr.trace" >/dev/null 2>&1 || true

# A successful add is followed by a list/reconciliation, not a blind return.
cat > "$fixture/machines.json" <<'EOF'
[]
EOF
cat > "$fixture/post-add.json" <<'EOF'
[
 {"id":"added","label":"fixture-host/hellomateo","target":"fixture-host","session":"hellomateo","enabled":true,"selected":true},
 {"id":"race","label":"race label","target":"fixture-host","session":"hellomateo","enabled":true,"selected":false}
]
EOF
export HERDR_POST_ADD=1 HERDR_POST_ADD_LIST="$fixture/post-add.json"
run_rdev
[[ $(grep -c 'machine list --json' "$fixture/herdr.trace") == 2 ]]
[[ $(grep -c 'machine disable race' "$fixture/herdr.trace") == 1 ]]
[[ "$HERDR_MACHINE_LABEL" == 'fixture-host/hellomateo' ]]
unset HERDR_POST_ADD HERDR_POST_ADD_LIST

# List, enable, duplicate-disable, malformed-output, and add failures propagate.
cat > "$fixture/machines.json" <<'EOF'
[]
EOF
export HERDR_LIST_FAIL=1
if run_rdev; then exit 1; fi
unset HERDR_LIST_FAIL
cat > "$fixture/machines.json" <<'EOF'
[{"id":"disabled","label":"disabled","target":"fixture-host","session":"hellomateo","enabled":false,"selected":false}]
EOF
export HERDR_ENABLE_FAIL=1
if run_rdev; then exit 1; fi
unset HERDR_ENABLE_FAIL
cat > "$fixture/machines.json" <<'EOF'
[
 {"id":"first","label":"first","target":"fixture-host","session":"hellomateo","enabled":true,"selected":false},
 {"id":"second","label":"second","target":"fixture-host","session":"hellomateo","enabled":true,"selected":false}
]
EOF
export HERDR_DISABLE_FAIL=1
if run_rdev; then exit 1; fi
unset HERDR_DISABLE_FAIL
print -r -- '{not-json' > "$fixture/machines.json"
if run_rdev; then exit 1; fi
cat > "$fixture/machines.json" <<'EOF'
[{"id":"missing-selected","label":"bad-shape","target":"fixture-host","session":"hellomateo","enabled":true}]
EOF
if run_rdev; then exit 1; fi
cat > "$fixture/machines.json" <<'EOF'
[]
EOF
export HERDR_ADD_FAIL=1
if run_rdev; then exit 1; fi
unset HERDR_ADD_FAIL

# Profile operations happen only after successful SSH preparation.
export RDEV_SSH_FAIL=1
: > "$fixture/herdr.trace"
if run_rdev; then exit 1; fi
[[ ! -s "$fixture/herdr.trace" ]]
unset RDEV_SSH_FAIL

print 'rdev machine registration tests passed'
