#!/usr/bin/env zsh

emulate -L zsh
set -euo pipefail
setopt typesetsilent

usage() {
  cat >&2 <<'EOF'
Usage:
  worktree-agent.zsh ensure <branch|pr-number> [--focus]
  worktree-agent.zsh launch <branch|pr-number> [--name <name>] [--kind <kind>]
      (--prompt <text> | --prompt-file <path>) [--focus]
EOF
}

fail() {
  print -u2 -r -- "$*"
  exit 1
}

[[ $# -ge 2 ]] || {
  usage
  exit 1
}

mode="$1"
target="$2"
shift 2

[[ "$mode" == ensure || "$mode" == launch ]] || {
  usage
  exit 1
}
[[ -n "$target" ]] || fail "A branch or PR number is required."

typeset agent_name=""
typeset kind="pi"
typeset prompt=""
typeset prompt_file=""
typeset focus=0

while (( $# > 0 )); do
  case "$1" in
    --name)
      (( $# >= 2 )) || fail "--name requires a value."
      agent_name="$2"
      shift 2
      ;;
    --kind)
      (( $# >= 2 )) || fail "--kind requires a value."
      kind="$2"
      shift 2
      ;;
    --prompt)
      (( $# >= 2 )) || fail "--prompt requires a value."
      prompt="$2"
      shift 2
      ;;
    --prompt-file)
      (( $# >= 2 )) || fail "--prompt-file requires a path."
      prompt_file="$2"
      shift 2
      ;;
    --focus)
      focus=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

if [[ "$mode" == ensure && ( -n "$agent_name" || "$kind" != pi || -n "$prompt" || -n "$prompt_file" ) ]]; then
  fail "Agent options are only valid with the launch command."
fi

if [[ "$mode" == launch ]]; then
  if [[ -n "$prompt" && -n "$prompt_file" ]]; then
    fail "Use either --prompt or --prompt-file, not both."
  fi
  if [[ -n "$prompt_file" ]]; then
    [[ -r "$prompt_file" ]] || fail "Prompt file is not readable: $prompt_file"
    prompt="$(<"$prompt_file")"
  fi
  [[ -n "$prompt" ]] || fail "launch requires --prompt or --prompt-file."
fi

[[ "${HERDR_ENV:-}" == 1 ]] || fail "This launcher must run inside a Herdr-managed pane (HERDR_ENV=1)."
[[ -n "${HERDR_WORKSPACE_ID:-}" ]] || fail "HERDR_WORKSPACE_ID is not set."
command -v herdr >/dev/null 2>&1 || fail "herdr is not on PATH."
command -v jq >/dev/null 2>&1 || fail "jq is not on PATH."
herdr workspace get "$HERDR_WORKSPACE_ID" >/dev/null || fail "The calling Herdr workspace is unavailable."
git rev-parse --git-dir >/dev/null 2>&1 || fail "Run this launcher from a Git worktree."

dotfiles="${RDEV_DOTFILES:-${LOCAL_DOTFILES:-$HOME/Developer/dotfiles}}"
hwtcreate="$dotfiles/zsh/functions/hwtcreate"
[[ -r "$hwtcreate" ]] || fail "Managed worktree helper not found: $hwtcreate"

before_workspace_ids="$(herdr workspace list | jq -r '.result.workspaces[]?.workspace_id')"

# hwtcreate is the authoritative project-worktree path. It sources wtensure and
# wtsetup, then opens or reuses the matching Herdr workspace. Keep focus stable
# while this background launcher runs.
source "$hwtcreate" --no-focus "$target" >&2

worktree_path="${WTENSURE_WORKTREE_PATH:-$PWD}"
worktree_label="${WTENSURE_WORKTREE_NAME:-${worktree_path:t}}"
[[ -d "$worktree_path" ]] || fail "Managed helper returned a missing worktree: $worktree_path"

target_workspace_id="$(_h_workspace_id_for_path_or_label "$worktree_path" "$worktree_label")"
[[ -n "$target_workspace_id" ]] || fail "Could not resolve the Herdr workspace for $worktree_path"

created_workspace=true
if print -r -- "$before_workspace_ids" | grep -Fxq -- "$target_workspace_id"; then
  created_workspace=false
fi

if [[ "$mode" == ensure ]]; then
  if (( focus )); then
    herdr workspace focus "$target_workspace_id" >/dev/null
  fi

  jq -n \
    --arg mode "$mode" \
    --arg target "$target" \
    --arg worktree_path "$worktree_path" \
    --arg worktree_label "$worktree_label" \
    --arg workspace_id "$target_workspace_id" \
    --argjson created_workspace "$created_workspace" \
    '{mode: $mode, target: $target, worktree_path: $worktree_path, worktree_label: $worktree_label, workspace_id: $workspace_id, created_workspace: $created_workspace}'
  exit 0
fi

normalize_agent_name() {
  local value="$1"
  value="$(print -nr -- "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$value" ]] || value="worktree"
  [[ "$value" == [a-z]* ]] || value="wt-$value"
  print -r -- "${value[1,32]}"
}

unique_agent_name() {
  local base="$1"
  local names candidate suffix prefix_length counter=2
  names="$(herdr agent list | jq -r '.result.agents[]? | (.name // .agent_name // .agent // empty)')"
  candidate="$base"

  while print -r -- "$names" | grep -Fxq -- "$candidate"; do
    suffix="-$counter"
    prefix_length=$((32 - ${#suffix}))
    candidate="${base[1,$prefix_length]}${suffix}"
    counter=$((counter + 1))
  done

  print -r -- "$candidate"
}

if [[ -n "$agent_name" && ! "$agent_name" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then
  fail "Agent names must match [a-z][a-z0-9_-]{0,31}: $agent_name"
fi

[[ -n "$agent_name" ]] || agent_name="$(normalize_agent_name "wt-$worktree_label")"
agent_name="$(unique_agent_name "$agent_name")"

typeset pane_id=""
typeset tab_id=""
typeset agent_started=0

cleanup_failed_tab() {
  local status=$?
  if (( status != 0 && agent_started == 0 )) && [[ -n "$tab_id" ]]; then
    herdr tab close "$tab_id" >/dev/null 2>&1 || true
  fi
  return $status
}
trap cleanup_failed_tab EXIT

if [[ "$created_workspace" == true ]]; then
  pane_id="$(
    herdr pane list --workspace "$target_workspace_id" \
      | jq -r --arg cwd "$worktree_path" '
          first(
            .result.panes[]?
            | select((.foreground_cwd // .cwd // "") == $cwd)
            | .pane_id
          ) // first(.result.panes[]?.pane_id) // empty
        '
  )"
else
  tab_json="$(
    herdr tab create \
      --workspace "$target_workspace_id" \
      --cwd "$worktree_path" \
      --label "$agent_name" \
      --no-focus
  )"
  tab_id="$(print -r -- "$tab_json" | jq -r '.result.tab.tab_id // .result.tab.id // empty')"
  pane_id="$(print -r -- "$tab_json" | jq -r '.result.root_pane.pane_id // .result.root_pane.id // empty')"
fi

[[ -n "$pane_id" ]] || fail "Could not find an available shell pane in workspace $target_workspace_id"

herdr agent start "$agent_name" --kind "$kind" --pane "$pane_id" >/dev/null
agent_started=1
herdr agent prompt "$agent_name" "$prompt" >/dev/null

if (( focus )); then
  herdr agent focus "$agent_name" >/dev/null
fi

trap - EXIT
jq -n \
  --arg mode "$mode" \
  --arg target "$target" \
  --arg worktree_path "$worktree_path" \
  --arg worktree_label "$worktree_label" \
  --arg workspace_id "$target_workspace_id" \
  --arg tab_id "$tab_id" \
  --arg pane_id "$pane_id" \
  --arg agent_name "$agent_name" \
  --arg kind "$kind" \
  --argjson created_workspace "$created_workspace" \
  '{mode: $mode, target: $target, worktree_path: $worktree_path, worktree_label: $worktree_label, workspace_id: $workspace_id, tab_id: (if $tab_id == "" then null else $tab_id end), pane_id: $pane_id, agent_name: $agent_name, kind: $kind, created_workspace: $created_workspace}'
