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
mkdir -p "$local_home/.config/gcloud/configurations" "$local_home/.config/gcloud/logs" "$remote_home/.config/gcloud/logs"
print -r -- fixture-credentials > "$local_home/.config/gcloud/credentials.db"
print -r -- $'[core]\naccount = dev@example.com' > "$local_home/.config/gcloud/configurations/config_default"
print -r -- local-log > "$local_home/.config/gcloud/logs/local.log"
print -r -- True > "$local_home/.config/gcloud/gce"
print -r -- remote-log > "$remote_home/.config/gcloud/logs/remote.log"
print -r -- stale > "$remote_home/.config/gcloud/stale.db"
mkdir -p "$local_home/.azure/logs" "$remote_home/.azure/logs"
print -r -- '{"subscriptions":[{"id":"fixture-subscription"}]}' > "$local_home/.azure/azureProfile.json"
print -r -- '{"AccessToken":{}}' > "$local_home/.azure/msal_token_cache.json"
print -r -- local-session > "$local_home/.azure/az.sess"
print -r -- local-log > "$local_home/.azure/logs/local.log"
print -r -- remote-log > "$remote_home/.azure/logs/remote.log"
print -r -- '[{"client_id":"stale"}]' > "$remote_home/.azure/service_principal_entries.json"
print -r -- '{"claudeAiOauth":{"accessToken":"claude-access","refreshToken":"claude-refresh","expiresAt":123},"mcpOAuth":{"local-only":{}}}' > "$local_home/.claude/.credentials.json"
print -r -- '{"claudeAiOauth":{"accessToken":"old","refreshToken":"old","stale":"remove-me","expiresAt":999},"mcpOAuth":{"remote-preserved":{}}}' > "$remote_home/.claude/.credentials.json"
: > "$fixture/ssh-trace"
: > "$fixture/security-trace"
keychain_mode=success
infisical_exp=4102444800

infisical_credentials() {
  local claims
  claims=$(print -rn -- "{\"exp\":$infisical_exp}" | base64 | tr '+/' '-_' | tr -d '=\n')
  print -rn -- "{\"email\":\"dev@example.com\",\"privateKey\":\"\",\"JTWToken\":\"e30.$claims.sig\",\"RefreshToken\":\"\"}"
}

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
  if [[ "$*" == *"-s infisical-cli"* ]]; then
    print -r -- "go-keyring-base64:$(infisical_credentials | base64 | tr -d '\n')"
    return
  fi
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
     \
    rauth --host fixture-host --user "$USER" --home "$remote_home" aws
)

[[ "$output" == *"Copied AWS auth to fixture-host:$USER:$remote_home/.aws"* ]]
cmp "$local_home/.aws/config" "$remote_home/.aws/config"
cmp "$local_home/.aws/sso/cache/fixture.json" "$remote_home/.aws/sso/cache/fixture.json"
! grep -q '^-t ' "$fixture/ssh-trace"

gcloud_output=$(
  HOME="$local_home" \
     \
    rauth --host fixture-host --user "$USER" --home "$remote_home" gcloud
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
    rauth --host fixture-host --user "$USER" --home "$remote_home" azure
)
[[ "$azure_output" == *"Copied Azure CLI auth to fixture-host:$USER:$remote_home/.azure"* ]]
cmp "$local_home/.azure/azureProfile.json" "$remote_home/.azure/azureProfile.json"
cmp "$local_home/.azure/msal_token_cache.json" "$remote_home/.azure/msal_token_cache.json"
[[ ! -e "$remote_home/.azure/service_principal_entries.json" ]]
[[ ! -e "$remote_home/.azure/az.sess" ]]
[[ ! -e "$remote_home/.azure/logs/local.log" ]]
[[ -f "$remote_home/.azure/logs/remote.log" ]]

mkdir -p "$fixture/no-azure-home"
if azure_missing=$(HOME="$fixture/no-azure-home" rauth --host fixture-host --user "$USER" --home "$remote_home" azure 2>&1); then
  print -u2 'rauth azure succeeded without a local login'
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
print -r -- '{"loggedInUserEmail":"dev@example.com","LoggedInUserDomain":"https://eu.infisical.com/api"}' \
  > "$local_home/.infisical/infisical-config.json"
infisical_home="$fixture/infisical-home"
mkdir -p "$remote_home/.local/bin"
# The remote runner uses a fixed PATH; expose this machine's node there.
mkdir -p "$infisical_home/.local/bin"
ln -s "$(command -v node)" "$infisical_home/.local/bin/node"
ln -s "$(command -v node)" "$remote_home/.local/bin/node"
infisical_output=$(HOME="$local_home"  \
  rauth --host fixture-host --user "$USER" --home "$infisical_home" infisical)
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
  rauth --host fixture-host --user "$USER" --home "$infisical_home" infisical >/dev/null
jq -e --arg p "$passphrase" '.vaultBackendPassphrase == $p and .telemetry == "keep" and (.loggedInUsers | length) == 1' \
  "$infisical_home/.infisical/infisical-config.json" >/dev/null
[[ "$(decrypt_infisical_vault "$infisical_home")" == "$(infisical_credentials)" ]]

# An expired local login is refused rather than copied.
vault_before=$(cat "$infisical_home/infisical-keyring/dev@example.com")
infisical_exp=1
if HOME="$local_home"  \
  rauth --host fixture-host --user "$USER" --home "$infisical_home" infisical 2>"$fixture/infisical-err"; then
  print -r -- 'expected an expired Infisical login to fail' >&2
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
    rauth --host fixture-host --user "$USER" --home "$remote_home" all
)
[[ "$all_output" == *"Copied Exa API key"* ]]
[[ "$all_output" == *"Copied Infisical login for dev@example.com"* ]]
[[ "$(decrypt_infisical_vault "$remote_home")" == "$(infisical_credentials)" ]]

# Provider, MCP and GitHub OAuth can never enter the copy path.
for spec in pi pi:all claude bridge codex gh mcp mcp:executor; do
  if rauth --host fixture-host --user "$USER" --home "$remote_home" "$spec" >/dev/null 2>&1; then
    print -u2 "OAuth copy unexpectedly accepted: $spec"
    exit 1
  fi
done
[[ ! -e "$remote_home/.pi/agent/auth.json" && ! -e "$remote_home/.pi/agent/mcp-auth.json" ]]
if rauth aws >/dev/null 2>&1; then
  print -u2 'Expected host-less credential transfer to fail'
  exit 1
fi
help=$(rauth --help 2>&1)
[[ "$help" == *'Never copies provider, MCP, or GitHub OAuth'* ]]
print 'Cloud/API-key transfer, private file permissions, and OAuth copy rejection tests passed'
