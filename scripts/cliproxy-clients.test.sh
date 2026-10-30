#!/usr/bin/env bash
# Offline fixtures for scripts/cliproxy-clients.sh: a temporary HOME, no network.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
script=$repo/scripts/cliproxy-clients.sh
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
toml_json() { yq -p toml -o json '.' "$HOME/.codex/config.toml"; }
endpoint=https://cliproxy-psteinroe.tail649856.ts.net:8317
key=$HOME/.config/cliproxy/access-key

# Without a key nothing is touched.
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.pi/agent"
printf '{"theme":"dark","env":{"KEEP":"1"}}\n' >"$HOME/.claude/settings.json"
cat >"$HOME/.codex/config.toml" <<'EOF'
model = "gpt-6-luna"
model_provider = "openai"

[mcp_servers.executor]
url = "https://executor.example.invalid/mcp"

[projects."/home/fixture/x"]
trust_level = "trusted"
EOF
cp "$HOME/.codex/config.toml" "$HOME/codex.orig"
printf '{"openai":{"type":"oauth"}}\n' >"$HOME/.pi/agent/auth.json"
printf '{"providers":{"ollama":{"baseUrl":"http://localhost:11434/v1"}}}\n' >"$HOME/.pi/agent/models.json"
bash "$script" 2>"$HOME/err"
grep -q 'no access key' "$HOME/err" || fail 'missing-key notice'
cmp -s "$HOME/.codex/config.toml" "$HOME/codex.orig" || fail 'Codex changed without a key'
[[ $(jq -r .env.ANTHROPIC_BASE_URL "$HOME/.claude/settings.json") == null ]] || fail 'Claude changed without a key'

# With a key, owned settings are set and unrelated settings stay.
mkdir -p "$(dirname "$key")"
printf 'fixture-key\n' >"$key"
bash "$script" >"$HOME/out" 2>"$HOME/err"
jq -e --arg url "$endpoint" --arg helper "cat '$key'" \
  '.theme == "dark" and .env.KEEP == "1" and .env.ANTHROPIC_BASE_URL == $url and .apiKeyHelper == $helper' \
  "$HOME/.claude/settings.json" >/dev/null || fail 'Claude settings merge'
toml_json | jq -e --arg url "$endpoint/v1" --arg key "$key" '
  .model_provider == "cliproxy" and .model == "gpt-6-luna"
  and .model_providers.cliproxy.base_url == $url
  and .model_providers.cliproxy.wire_api == "responses"
  and .model_providers.cliproxy.auth.command == "cat"
  and .model_providers.cliproxy.auth.args == [$key]
  and .mcp_servers.executor.url == "https://executor.example.invalid/mcp"
  and .projects["/home/fixture/x"].trust_level == "trusted"' >/dev/null || fail 'Codex config'
[[ $(grep -c '^model_provider' "$HOME/.codex/config.toml") == 1 ]] || fail 'duplicate model_provider'
! grep -q fixture-key "$HOME/.codex/config.toml" "$HOME/.claude/settings.json" || fail 'key copied into a config file'

# Pi keeps its own OpenAI login until it is logged out.
grep -q '/logout openai' "$HOME/err" || fail 'Pi logout notice'
[[ $(jq -r '.providers.openai' "$HOME/.pi/agent/models.json") == null ]] || fail 'Pi switched while logged in'
grep -q 'Claude Code, Codex use' "$HOME/out" || fail 'summary without Pi'

printf '{}\n' >"$HOME/.pi/agent/auth.json"
bash "$script" >"$HOME/out"
jq -e --arg url "$endpoint/v1" --arg key "!cat '$key'" \
  '.providers.ollama.baseUrl == "http://localhost:11434/v1" and .providers.openai.baseUrl == $url and .providers.openai.apiKey == $key' \
  "$HOME/.pi/agent/models.json" >/dev/null || fail 'Pi models merge'
grep -q 'Claude Code, Codex, Pi use' "$HOME/out" || fail 'summary with Pi'

# Reruns are idempotent; private permissions are kept.
for file in .claude/settings.json .codex/config.toml .pi/agent/models.json; do cp "$HOME/$file" "$HOME/$(basename "$file").1"; done
bash "$script" >/dev/null
for file in .claude/settings.json .codex/config.toml .pi/agent/models.json; do
  cmp -s "$HOME/$file" "$HOME/$(basename "$file").1" || fail "rerun changed $file"
  [[ $(stat -f %Lp "$HOME/$file" 2>/dev/null || stat -c %a "$HOME/$file") == 600 ]] || fail "$file not private"
done

# Fresh homes get valid files too.
rm -rf "$HOME/.claude" "$HOME/.codex"
bash "$script" >/dev/null
toml_json | jq -e '.model_provider == "cliproxy"' >/dev/null || fail 'fresh Codex config'
jq -e '.apiKeyHelper' "$HOME/.claude/settings.json" >/dev/null || fail 'fresh Claude settings'

printf 'CLIProxy client configuration fixtures passed\n'
