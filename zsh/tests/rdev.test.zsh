#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/dotfiles/zsh/functions"
cat > "$fixture/dotfiles/zsh/functions/_herdr_binary" <<'EOF'
_herdr_binary() {
  print -r -- "$HERDR_BIN"
}
EOF
cat > "$fixture/herdr" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$fixture/herdr"

ssh() {
  typeset -g RDEV_TEST_RUNNER=${@[-1]}
}

fpath=("$repo_root/zsh/functions" $fpath)
autoload -Uz rdev

# Local helpers use RDEV_DOTFILES while they run. That local path must never be
# mistaken for the path to the dotfiles checkout on the remote machine.
export RDEV_DOTFILES=/Users/test/Developer/dotfiles
RDEV_HOST=fixture-host \
  RDEV_REMOTE_USER=test \
  RDEV_HOME=/home/test \
  LOCAL_DOTFILES="$fixture/dotfiles" \
  HERDR_BIN="$fixture/herdr" \
  rdev hellomateo

assignment=${RDEV_TEST_RUNNER%%; cmd=*}
encoded=${(Q)${assignment#encoded=}}
prepare_cmd=$(printf '%s' "$encoded" | base64 -d)

[[ "$prepare_cmd" != *'/Users/test/Developer/dotfiles/zsh/functions/hprepare'* ]]
[[ "$prepare_cmd" == *'/home/test/Developer/dotfiles/zsh/functions/hprepare'* ]]

print 'rdev remote path test passed'
