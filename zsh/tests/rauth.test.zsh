#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
local_home="$fixture/local-home"
remote_home="$fixture/remote-home"
mkdir -p "$local_home/.aws/sso/cache" "$remote_home"
print -r -- $'[default]\nregion = eu-central-1' > "$local_home/.aws/config"
print -r -- '{"accessToken":"fixture-token"}' > "$local_home/.aws/sso/cache/fixture.json"
: > "$fixture/ssh-trace"

ssh() {
  print -r -- "$*" >> "$fixture/ssh-trace"
  [[ "${1:-}" != -t ]]
  local runner=${@[-1]}
  eval "$runner"
}

fpath=("$repo_root/zsh/functions" $fpath)
autoload -Uz rauth

output=$(
  HOME="$local_home" \
    RDEV_REMOTE_USER="$USER" \
    rauth --host fixture-host --home "$remote_home" aws
)

[[ "$output" == *"Copied AWS auth to fixture-host:$USER:$remote_home/.aws"* ]]
cmp "$local_home/.aws/config" "$remote_home/.aws/config"
cmp "$local_home/.aws/sso/cache/fixture.json" "$remote_home/.aws/sso/cache/fixture.json"
! grep -q '^-t ' "$fixture/ssh-trace"

help=$(rauth --help 2>&1)
[[ "$help" == *'aws                         copy AWS config and cached sessions to ~/.aws'* ]]

print 'rauth AWS auth copy test passed'
