source "${0:A:h}/lib/project-context.zsh" || exit 1
_ws_resolve_project_context || exit 1

pane_id="${HERDR_PANE_ID:-}"
workspace_id="${HERDR_WORKSPACE_ID:-}"
if [[ -z "$pane_id" || -z "$workspace_id" ]]; then
  echo "No current Herdr pane/workspace id; cannot bootstrap panes." >&2
  exit 1
fi

_hws_pane_id_from_json() {
  jq -r '.. | objects | (.pane_id? // .id? // empty)' 2>/dev/null | head -n 1
}

_hws_split() {
  local source_pane="$1"
  local direction="$2"
  local ratio="$3"
  local label="$4"
  local focus="${5:-0}"
  local json new_id
  if [[ "$focus" == 1 ]]; then
    json=$(herdr pane split "$source_pane" --direction "$direction" --ratio "$ratio" --cwd "$WS_PROJECT_CWD" --focus) || return
  else
    json=$(herdr pane split "$source_pane" --direction "$direction" --ratio "$ratio" --cwd "$WS_PROJECT_CWD" --no-focus) || return
  fi
  new_id=$(print -r -- "$json" | _hws_pane_id_from_json)
  [[ -n "$new_id" ]] && herdr pane rename "$new_id" "$label" >/dev/null 2>&1 || true
  print -r -- "$new_id"
}

_hws_default_bootstrap() {
  local pane_count agent_id shell_id
  pane_count=$(herdr pane list --workspace "$workspace_id" 2>/dev/null | jq -r '.result.panes | length' 2>/dev/null || echo 0)
  if (( pane_count > 1 )); then
    echo "Workspace already has $pane_count panes; leaving layout unchanged."
    return 0
  fi

  herdr pane rename "$pane_id" main >/dev/null 2>&1 || true
  agent_id="$(_hws_split "$pane_id" right 0.50 agent 0)" || return
  shell_id="$(_hws_split "$pane_id" down 0.35 shell 0)" || true

  # Keep bootstrap safe: create named panes only. Do not auto-start servers,
  # tests, editors, or agents; repo-specific hooks can opt into that later.
  herdr pane focus --pane "$pane_id" >/dev/null 2>&1 || true
  echo "Bootstrapped default layout: main${shell_id:+, shell}${agent_id:+, agent}."
}

layout_hook="$WS_DOTFILES/herdr/bootstrap/$WS_PROJECT_NAME.zsh"
if [[ -f "$layout_hook" ]]; then
  source "$layout_hook"
else
  _hws_default_bootstrap
fi
