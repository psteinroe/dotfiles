#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
local_home="$fixture/local-home"
remote_home="$fixture/remote-home"
mkdir -p "$local_home/.aws/sso/cache" "$local_home/.claude" "$remote_home/.claude"
printf '%s\n' $'[default]\nregion = eu-central-1' > "$local_home/.aws/config"
printf '%s\n' '{"accessToken":"fixture-token"}' > "$local_home/.aws/sso/cache/fixture.json"
mkdir -p "$local_home/.config/gcloud/configurations" "$local_home/.config/gcloud/logs" "$remote_home/.config/gcloud/logs"
printf '%s\n' fixture-credentials > "$local_home/.config/gcloud/credentials.db"
printf '%s\n' $'[core]\naccount = dev@example.com' > "$local_home/.config/gcloud/configurations/config_default"
printf '%s\n' local-log > "$local_home/.config/gcloud/logs/local.log"
printf '%s\n' True > "$local_home/.config/gcloud/gce"
printf '%s\n' remote-log > "$remote_home/.config/gcloud/logs/remote.log"
printf '%s\n' stale > "$remote_home/.config/gcloud/stale.db"
mkdir -p "$local_home/.azure/logs" "$remote_home/.azure/logs"
printf '%s\n' '{"subscriptions":[{"id":"fixture-subscription"}]}' > "$local_home/.azure/azureProfile.json"
printf '%s\n' '{"AccessToken":{}}' > "$local_home/.azure/msal_token_cache.json"
printf '%s\n' local-session > "$local_home/.azure/az.sess"
printf '%s\n' local-log > "$local_home/.azure/logs/local.log"
printf '%s\n' remote-log > "$remote_home/.azure/logs/remote.log"
printf '%s\n' '[{"client_id":"stale"}]' > "$remote_home/.azure/service_principal_entries.json"
printf '%s\n' '{"claudeAiOauth":{"accessToken":"claude-access","refreshToken":"claude-refresh","expiresAt":123},"mcpOAuth":{"local-only":{}}}' > "$local_home/.claude/.credentials.json"
printf '%s\n' '{"claudeAiOauth":{"accessToken":"old","refreshToken":"old","stale":"remove-me","expiresAt":999},"mcpOAuth":{"remote-preserved":{}}}' > "$remote_home/.claude/.credentials.json"
: > "$fixture/ssh-trace"
: > "$fixture/security-trace"
keychain_mode=success
infisical_exp=4102444800

infisical_credentials() {
  local claims
  claims=$(printf '%s' "{\"exp\":$infisical_exp}" | base64 | tr '+/' '-_' | tr -d '=\n')
  printf '%s' "{\"email\":\"dev@example.com\",\"privateKey\":\"\",\"JTWToken\":\"e30.$claims.sig\",\"RefreshToken\":\"\"}"
}

ssh() {
  printf '%s\n' "$*" >> "$fixture/ssh-trace"
  [[ $# == 2 && $1 == fixture-host ]] || { printf 'Unexpected SSH arguments\n' >&2; return 99; }
  if [[ $2 == *'$(id -un)'* ]]; then
    printf '%s\n%s\n' "$USER" "${AUTH_FIXTURE_HOME:-$fixture/remote-home}"
    return
  fi
  [[ $2 == encoded=* ]] || { printf 'Unexpected SSH command\n' >&2; return 99; }
  (eval "$2")
}

uname() {
  [[ "${1:-}" == -s || $# -eq 0 ]] && printf '%s\n' Darwin
}

security() {
  printf '%s\n' "$*" >> "$fixture/security-trace"
  if [[ "$*" == *"-s infisical-cli"* ]]; then
    printf '%s\n' "go-keyring-base64:$(infisical_credentials | base64 | tr -d '\n')"
    return
  fi
  case "$keychain_mode" in
    success)
      printf '%s\n' '{"claudeAiOauth":{"accessToken":"keychain-access","refreshToken":"keychain-refresh"}}'
      ;;
    malformed)
      printf '%s\n' '{"claudeAiOauth":{}}'
      ;;
    *)
      return 1
      ;;
  esac
}

source "$repo_root/bin/remote"

output=$(
  HOME="$local_home" \
     \
    _remote_main auth fixture-host aws
)

[[ "$output" == *"Copied AWS auth to fixture-host:$USER:$remote_home/.aws"* ]]
cmp "$local_home/.aws/config" "$remote_home/.aws/config"
cmp "$local_home/.aws/sso/cache/fixture.json" "$remote_home/.aws/sso/cache/fixture.json"
! grep -q '^-t ' "$fixture/ssh-trace"

gcloud_output=$(
  HOME="$local_home" \
     \
    _remote_main auth fixture-host gcloud
)
[[ "$gcloud_output" == *"Copied gcloud auth to fixture-host:$USER:$remote_home/.config/gcloud"* ]]
cmp "$local_home/.config/gcloud/credentials.db" "$remote_home/.config/gcloud/credentials.db"
cmp "$local_home/.config/gcloud/configurations/config_default" "$remote_home/.config/gcloud/configurations/config_default"
[[ -f "$remote_home/.config/gcloud/logs/remote.log" ]]
[[ ! -e "$remote_home/.config/gcloud/logs/local.log" ]]
[[ ! -e "$remote_home/.config/gcloud/gce" ]]
[[ ! -e "$remote_home/.config/gcloud/stale.db" ]]

azure_output=$(
  HOME="$local_home" \
     \
    _remote_main auth fixture-host azure
)
[[ "$azure_output" == *"Copied Azure CLI auth to fixture-host:$USER:$remote_home/.azure"* ]]
cmp "$local_home/.azure/azureProfile.json" "$remote_home/.azure/azureProfile.json"
cmp "$local_home/.azure/msal_token_cache.json" "$remote_home/.azure/msal_token_cache.json"
[[ ! -e "$remote_home/.azure/service_principal_entries.json" ]]
[[ ! -e "$remote_home/.azure/az.sess" ]]
[[ ! -e "$remote_home/.azure/logs/local.log" ]]
[[ -f "$remote_home/.azure/logs/remote.log" ]]

mkdir -p "$fixture/no-azure-home"
if azure_missing=$(HOME="$fixture/no-azure-home" _remote_main auth fixture-host azure 2>&1); then
  printf '%s\n' 'remote auth azure succeeded without a local login'
  exit 1
fi
[[ "$azure_missing" == *'No Azure CLI login found'*'Run: az login'* ]]

# Infisical: macOS Keychain (go-keyring) login -> remote encrypted file vault.
decrypt_infisical_vault() {
  node - "$1" <<'JS'
const fs = require("fs"), crypto = require("crypto");
const home = process.argv[2];
const config = JSON.parse(fs.readFileSync(`${home}/.infisical/infisical-config.json`, "utf8"));
const [ph, ek, iv, ct, tag] = fs.readFileSync(`${home}/infisical-keyring/${config.loggedInUserEmail}`, "utf8").split(".");
const b = (s) => Buffer.from(s, "base64url");
const header = JSON.parse(b(ph));
const salt = Buffer.concat([Buffer.from(header.alg), Buffer.from([0]), b(header.p2s)]);
const kek = crypto.pbkdf2Sync(Buffer.from(config.vaultBackendPassphrase, "base64"), salt, header.p2c, 16, "sha256");
const unwrap = crypto.createDecipheriv("id-aes128-wrap", kek, Buffer.from("A6A6A6A6A6A6A6A6", "hex"));
const cek = Buffer.concat([unwrap.update(b(ek)), unwrap.final()]);
const gcm = crypto.createDecipheriv("aes-256-gcm", cek, b(iv));
gcm.setAAD(Buffer.from(ph)); gcm.setAuthTag(b(tag));
process.stdout.write(JSON.parse(Buffer.concat([gcm.update(b(ct)), gcm.final()]).toString()));
JS
}

mkdir -p "$local_home/.infisical"
printf '%s\n' '{"loggedInUserEmail":"dev@example.com","LoggedInUserDomain":"https://eu.infisical.com/api"}' \
  > "$local_home/.infisical/infisical-config.json"
infisical_home="$fixture/infisical-home"
mkdir -p "$remote_home/.local/bin"
ln -s "$(command -v jq)" "$remote_home/.local/bin/jq"
# The remote runner uses a fixed PATH; expose this machine's node there.
mkdir -p "$infisical_home/.local/bin"
ln -s "$(command -v jq)" "$infisical_home/.local/bin/jq"
ln -s "$(command -v node)" "$infisical_home/.local/bin/node"
ln -s "$(command -v node)" "$remote_home/.local/bin/node"
infisical_output=$(HOME="$local_home"  \
  AUTH_FIXTURE_HOME="$infisical_home" _remote_main auth fixture-host infisical)
[[ "$infisical_output" == *"Copied Infisical login for dev@example.com"* ]]
[[ "$(decrypt_infisical_vault "$infisical_home")" == "$(infisical_credentials)" ]]
jq -e '.vaultBackendType == "file" and .loggedInUserEmail == "dev@example.com"
  and .LoggedInUserDomain == "https://eu.infisical.com/api"
  and .loggedInUsers == [{"email": "dev@example.com", "domain": "https://eu.infisical.com/api"}]' \
  "$infisical_home/.infisical/infisical-config.json" >/dev/null
if [[ "$OSTYPE" == darwin* ]]; then
  [[ "$(stat -f '%Lp' "$infisical_home/infisical-keyring/dev@example.com")" == 600 ]]
else
  [[ "$(stat -c '%a' "$infisical_home/infisical-keyring/dev@example.com")" == 600 ]]
fi

# A second copy keeps the remote passphrase (other vault entries depend on it)
# and unrelated config, without duplicating the logged-in user.
jq '.telemetry = "keep"' "$infisical_home/.infisical/infisical-config.json" > "$fixture/infisical-config"
mv "$fixture/infisical-config" "$infisical_home/.infisical/infisical-config.json"
passphrase=$(jq -r .vaultBackendPassphrase "$infisical_home/.infisical/infisical-config.json")
HOME="$local_home"  \
  AUTH_FIXTURE_HOME="$infisical_home" _remote_main auth fixture-host infisical >/dev/null
jq -e --arg p "$passphrase" '.vaultBackendPassphrase == $p and .telemetry == "keep" and (.loggedInUsers | length) == 1' \
  "$infisical_home/.infisical/infisical-config.json" >/dev/null
[[ "$(decrypt_infisical_vault "$infisical_home")" == "$(infisical_credentials)" ]]

# An expired local login is refused rather than copied.
vault_before=$(cat "$infisical_home/infisical-keyring/dev@example.com")
infisical_exp=1
if HOME="$local_home"  \
  AUTH_FIXTURE_HOME="$infisical_home" _remote_main auth fixture-host infisical 2>"$fixture/infisical-err"; then
  printf '%s\n' 'expected an expired Infisical login to fail' >&2
  exit 1
fi
grep -q 'Local Infisical login has expired' "$fixture/infisical-err"
[[ "$(cat "$infisical_home/infisical-keyring/dev@example.com")" == "$vault_before" ]]
infisical_exp=4102444800

all_output=$(
  HOME="$local_home"  \
    PATH="$remote_home/.local/bin:$PATH" \
    CLAUDE_CREDENTIALS_FILE="$local_home/.claude/.credentials.json" \
    EXA_API_KEY=exa-fixture \
    _remote_main auth fixture-host all
)
[[ "$all_output" == *"Copied Exa API key"* ]]
[[ "$all_output" == *"Copied Infisical login for dev@example.com"* ]]
[[ "$(decrypt_infisical_vault "$remote_home")" == "$(infisical_credentials)" ]]

# Provider, MCP and GitHub OAuth can never enter the copy path.
for spec in pi pi:all claude bridge codex gh mcp mcp:executor; do
  if ( _remote_auth_cloud fixture-host "$spec" ) >/dev/null 2>&1; then
    printf '%s\n' "OAuth copy unexpectedly accepted: $spec" >&2
    exit 1
  fi
done
[[ ! -e "$remote_home/.pi/agent/auth.json" && ! -e "$remote_home/.pi/agent/mcp-auth.json" ]]
if ( _remote_main auth ) >/dev/null 2>&1; then
  printf '%s\n' 'Expected host-less credential transfer to fail'
  exit 1
fi
help=$(_remote_main --help 2>&1)
[[ "$help" == *'Never copies provider, MCP, or GitHub OAuth'* ]]
printf '%s\n' 'Cloud/API-key transfer, private file permissions, and OAuth copy rejection tests passed'
