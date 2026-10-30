#!/usr/bin/env bash
# Point Claude Code, Codex and Pi in their standard homes at the owner's CLIProxy.
# Run by Home Manager activation and, on hosts without it, by `remote auth HOST cliproxy`.
# Each client reads ~/.config/cliproxy/access-key at request time; no config file holds it.
set -euo pipefail
umask 077

endpoint=https://cliproxy-psteinroe.tail649856.ts.net:8317
key="$HOME/.config/cliproxy/access-key"
begin='# >>> dotfiles cliproxy'
end='# <<< dotfiles cliproxy'

if [[ ! -s $key ]]; then
  printf 'CLIProxy: no access key at %s; clients keep their current providers.\n' "$key" >&2
  exit 0
fi
command -v jq >/dev/null || { printf 'CLIProxy: jq is required.\n' >&2; exit 1; }

# Replace a JSON file atomically, keeping every key this script does not own.
merge_json() {
  local file=$1 filter=$2 tmp
  shift 2
  mkdir -p "$(dirname "$file")"
  [[ -s $file ]] || printf '{}\n' >"$file"
  tmp=$(mktemp "$file.XXXXXX")
  jq "$@" "$filter" "$file" >"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

# Claude Code: T3, the CLI and Claude Bridge all read user settings.
merge_json "$HOME/.claude/settings.json" \
  '.env.ANTHROPIC_BASE_URL = $url | .apiKeyHelper = $helper' \
  --arg url "$endpoint" --arg helper "cat '$key'"

# Codex: one managed provider block. A top-level key must precede every table,
# so the selected provider goes first and any earlier selection is dropped.
codex="$HOME/.codex/config.toml"
mkdir -p "$(dirname "$codex")"
touch "$codex"
tmp=$(mktemp "$codex.XXXXXX")
{
  printf 'model_provider = "cliproxy" %s\n' "$begin"
  awk -v begin="$begin" -v end="$end" '
    index($0, begin) && /^model_provider/ { next }
    index($0, begin) { skip = 1; next }
    skip && index($0, end) { skip = 0; next }
    skip { next }
    /^\[/ { table = 1 }
    !table && /^[[:space:]]*model_provider[[:space:]]*=/ { next }
    { print }
  ' "$codex"
  printf '%s\n[model_providers.cliproxy]\nname = "CLIProxy"\nbase_url = "%s/v1"\nwire_api = "responses"\n\n' "$begin" "$endpoint"
  printf '[model_providers.cliproxy.auth]\ncommand = "cat"\nargs = ["%s"]\n%s\n' "$key" "$end"
} >"$tmp"
chmod 600 "$tmp"
mv "$tmp" "$codex"

clients='Claude Code, Codex'
# Pi: a stored OpenAI login outranks models.json, so switch only after logout.
if [[ -d $HOME/.pi/agent ]]; then
  if jq -e '.openai' "$HOME/.pi/agent/auth.json" >/dev/null 2>&1; then
    printf 'CLIProxy: Pi still has its own OpenAI login. Run /logout openai in Pi, then rerun this.\n' >&2
  else
    merge_json "$HOME/.pi/agent/models.json" \
      '.providers.openai.baseUrl = $url | .providers.openai.apiKey = $key' \
      --arg url "$endpoint/v1" --arg key "!cat '$key'"
    clients+=', Pi'
  fi
fi

printf 'CLIProxy: %s use %s\n' "$clients" "$endpoint"
