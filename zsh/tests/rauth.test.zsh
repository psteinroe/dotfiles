#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
local_home="$fixture/local-home"
remote_home="$fixture/remote-home"
mkdir -p "$local_home/.aws/sso/cache" "$local_home/.claude" "$remote_home/.claude"
print -r -- $'[default]\nregion = eu-central-1' > "$local_home/.aws/config"
print -r -- '{"accessToken":"fixture-token"}' > "$local_home/.aws/sso/cache/fixture.json"
print -r -- '{"claudeAiOauth":{"accessToken":"claude-access","refreshToken":"claude-refresh","expiresAt":123},"mcpOAuth":{"local-only":{}}}' > "$local_home/.claude/.credentials.json"
print -r -- '{"claudeAiOauth":{"accessToken":"old","refreshToken":"old","stale":"remove-me","expiresAt":999},"mcpOAuth":{"remote-preserved":{}}}' > "$remote_home/.claude/.credentials.json"
: > "$fixture/ssh-trace"
: > "$fixture/security-trace"
keychain_mode=success

ssh() {
  print -r -- "$*" >> "$fixture/ssh-trace"
  [[ "${1:-}" != -t ]]
  local runner=${@[-1]}
  eval "$runner"
}

uname() {
  [[ "${1:-}" == -s || $# -eq 0 ]] && print -r -- Darwin
}

security() {
  print -r -- "$*" >> "$fixture/security-trace"
  case "$keychain_mode" in
    success)
      print -r -- '{"claudeAiOauth":{"accessToken":"keychain-access","refreshToken":"keychain-refresh"}}'
      ;;
    malformed)
      print -r -- '{"claudeAiOauth":{}}'
      ;;
    *)
      return 1
      ;;
  esac
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

claude_output=$(
  HOME="$local_home" \
    CLAUDE_CREDENTIALS_FILE="$local_home/.claude/.credentials.json" \
    RDEV_REMOTE_USER="$USER" \
    rauth --host fixture-host --home "$remote_home" claude
)
[[ "$claude_output" == *"Copied Claude Code OAuth credentials for pi-claude-bridge to fixture-host:$USER:$remote_home/.claude/.credentials.json"* ]]
[[ "$(jq -r '.claudeAiOauth.accessToken' "$remote_home/.claude/.credentials.json")" == claude-access ]]
[[ "$(jq -r '.claudeAiOauth.refreshToken' "$remote_home/.claude/.credentials.json")" == claude-refresh ]]
[[ "$(jq -r '.claudeAiOauth.expiresAt' "$remote_home/.claude/.credentials.json")" == 123 ]]
[[ "$(jq -r '.claudeAiOauth | has("stale")' "$remote_home/.claude/.credentials.json")" == false ]]
[[ "$(jq -r '.mcpOAuth | has("remote-preserved")' "$remote_home/.claude/.credentials.json")" == true ]]
[[ "$(jq -r '.mcpOAuth | has("local-only")' "$remote_home/.claude/.credentials.json")" == false ]]
if [[ "$OSTYPE" == darwin* ]]; then
  [[ "$(stat -f '%Lp' "$remote_home/.claude/.credentials.json")" == 600 ]]
else
  [[ "$(stat -c '%a' "$remote_home/.claude/.credentials.json")" == 600 ]]
fi
[[ ! -s "$fixture/security-trace" ]]

keychain_home="$fixture/keychain-home"
mkdir -p "$keychain_home"
HOME="$local_home" RDEV_REMOTE_USER="$USER" \
  rauth --host fixture-host --home "$keychain_home" claude >/dev/null
[[ "$(jq -r '.claudeAiOauth.accessToken' "$keychain_home/.claude/.credentials.json")" == keychain-access ]]
[[ -s "$fixture/security-trace" ]]

keychain_mode=malformed
fallback_home="$fixture/fallback-home"
mkdir -p "$fallback_home"
HOME="$local_home" RDEV_REMOTE_USER="$USER" \
  rauth --host fixture-host --home "$fallback_home" claude >/dev/null
[[ "$(jq -r '.claudeAiOauth.accessToken' "$fallback_home/.claude/.credentials.json")" == claude-access ]]

bridge_home="$fixture/bridge-home"
mkdir -p "$bridge_home"
HOME="$local_home" \
  CLAUDE_CREDENTIALS_FILE="$local_home/.claude/.credentials.json" \
  RDEV_REMOTE_USER="$USER" \
  rauth --host fixture-host --home "$bridge_home" bridge >/dev/null
[[ "$(jq -r '.claudeAiOauth.accessToken' "$bridge_home/.claude/.credentials.json")" == claude-access ]]

help=$(rauth --help 2>&1)
[[ "$help" == *'all                         copy gh, Pi, Claude/bridge, MCP, Exa, and AWS auth'* ]]
[[ "$help" == *'claude                      copy Claude Code OAuth used by pi-claude-bridge'* ]]
[[ "$help" == *'aws                         copy AWS config and cached sessions to ~/.aws'* ]]

print 'rauth AWS and Claude Bridge auth copy tests passed'
