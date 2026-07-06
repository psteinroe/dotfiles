# Shared context helpers for psteinroe.worktree-sync.

# Herdr plugin panes run zsh with user shell options. If TYPESET_SILENT is
# unset, repeated `local name` declarations can print `name=value`, polluting
# menu data captured via command substitution.
setopt typesetsilent

export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

_ws_dotfiles_dir() {
  if [[ -n "${RDEV_DOTFILES:-}" && -d "$RDEV_DOTFILES" ]]; then
    print -r -- "$RDEV_DOTFILES"
  elif [[ -d "$HOME/Developer/dotfiles" ]]; then
    print -r -- "$HOME/Developer/dotfiles"
  else
    print -r -- "$(cd "${0:A:h}/../../.." 2>/dev/null && pwd)"
  fi
}

typeset -g WS_PLUGIN_DIR="${0:A:h:h}"
typeset -g WS_DOTFILES="$(_ws_dotfiles_dir)"
source "$WS_DOTFILES/zsh/functions/_herdr_worktree_helpers" || return

_ws_session_json() {
  local session_dir
  if [[ -n "${HERDR_SOCKET_PATH:-}" ]]; then
    session_dir="$(dirname "$HERDR_SOCKET_PATH")"
  elif [[ -n "${HERDR_SESSION:-}" && "$HERDR_SESSION" != "default" ]]; then
    session_dir="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/sessions/$HERDR_SESSION"
  else
    session_dir="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
  fi
  print -r -- "$session_dir/session.json"
}

_ws_workspace_cwd() {
  local workspace_id="${HERDR_WORKSPACE_ID:-}"
  local session_json
  session_json="$(_ws_session_json)"

  if [[ -n "$workspace_id" && -r "$session_json" ]] && command -v jq >/dev/null 2>&1; then
    jq -r --arg id "$workspace_id" '.workspaces[]? | select(.id == $id) | .identity_cwd // empty' "$session_json" 2>/dev/null | head -n 1
    return 0
  fi

  if [[ -n "${HERDR_PLUGIN_CONTEXT_JSON:-}" ]] && command -v jq >/dev/null 2>&1; then
    print -r -- "$HERDR_PLUGIN_CONTEXT_JSON" \
      | jq -r '.. | objects | (.cwd? // .identity_cwd? // .path? // empty)' 2>/dev/null \
      | grep '^/' \
      | head -n 1
    return 0
  fi

  pwd
}

_ws_resolve_project_context() {
  local cwd repo_hint fallback_root fallback_cwd
  cwd="${HWS_PROJECT_CWD:-$(_ws_workspace_cwd)}"

  if [[ -n "$cwd" && -e "$cwd" ]]; then
    if cd "$cwd" 2>/dev/null && _h_repo_context >/dev/null 2>&1; then
      typeset -g WS_PROJECT_CWD="$cwd"
      typeset -g WS_PROJECT_NAME="$H_REPO_NAME"
      typeset -g WS_PROJECT_ROOT="$H_REPO_ROOT"
      typeset -g WS_WORKTREE_ROOT="$H_WORKTREE_ROOT"
      return 0
    fi
  fi

  # If a pane has drifted to ~, plugin actions still run inside a named Herdr
  # session. Recover the repo context from the session name and the standard
  # ~/Developer/<repo>.git worktree root instead of silently doing nothing.
  repo_hint="${HWS_PROJECT_NAME:-${HERDR_SESSION:-}}"
  if [[ -n "$repo_hint" && "$repo_hint" != "default" ]]; then
    fallback_root="$HOME/Developer/$repo_hint.git"
    if [[ -d "$fallback_root" ]]; then
      cd "$fallback_root" || return
      fallback_cwd="$(_h_git_worktree_paths | head -n 1)"
      [[ -n "$fallback_cwd" ]] || fallback_cwd="$fallback_root"
      typeset -g H_REPO_ROOT="$fallback_root"
      typeset -g H_REPO_NAME="$repo_hint"
      typeset -g H_WORKTREE_ROOT="$fallback_root"
      typeset -g WS_PROJECT_CWD="$fallback_cwd"
      typeset -g WS_PROJECT_NAME="$repo_hint"
      typeset -g WS_PROJECT_ROOT="$fallback_root"
      typeset -g WS_WORKTREE_ROOT="$fallback_root"
      return 0
    fi
  fi

  echo "Open this action from a project/worktree workspace." >&2
  return 1
}

_ws_workspace_id_for_path() {
  local needle="$1"
  local session_json id
  session_json="$(_ws_session_json)"
  [[ -r "$session_json" ]] || return 0
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if herdr workspace get "$id" >/dev/null 2>&1; then
      print -r -- "$id"
      return 0
    fi
  done < <(jq -r --arg cwd "$needle" '.workspaces[]? | select((.identity_cwd // "") == $cwd) | .id' "$session_json" 2>/dev/null)
}

_ws_workspace_has_pane_at_path() {
  local id="$1"
  local wt_path="$2"
  command -v jq >/dev/null 2>&1 || return 1
  herdr pane list --workspace "$id" 2>/dev/null \
    | jq -e --arg cwd "$wt_path" '
        .result.panes[]?
        # Prefer the live/foreground cwd when Herdr has it. A pane that was
        # originally created in a worktree but is now sitting in ~ should not
        # count as "opened" for that worktree.
        | select(
            if ((.foreground_cwd // "") != "") then
              .foreground_cwd == $cwd
            else
              (.cwd // "") == $cwd
            end
          )
      ' >/dev/null 2>&1
}

_ws_focus_or_create_workspace() {
  local wt_path="$1"
  local label="$2"
  local id
  id="$(_ws_workspace_id_for_path "$wt_path")"
  if [[ -n "$id" ]]; then
    herdr workspace focus "$id" >/dev/null || return

    # If this workspace was previously left in ~ or another directory, focusing
    # it alone feels like the selector opened the wrong place. Ensure there is
    # always a focused tab rooted at the selected Git worktree.
    if ! _ws_workspace_has_pane_at_path "$id" "$wt_path"; then
      herdr tab create --workspace "$id" --cwd "$wt_path" --label "$label" --focus >/dev/null || return
    fi
  else
    herdr workspace create --cwd "$wt_path" --label "$label" --focus >/dev/null || return
  fi
}

_ws_open_manager() {
  local mode="${1:-manager}"
  local -a pane_args
  _ws_resolve_project_context || return

  pane_args=(
    --plugin psteinroe.worktree-sync
    --entrypoint manager
    --placement overlay
    --env "HWS_MODE=$mode"
    --env "HWS_PROJECT_CWD=$WS_PROJECT_CWD"
    --env "HWS_PROJECT_NAME=$WS_PROJECT_NAME"
    --env "HWS_PROJECT_ROOT=$WS_PROJECT_ROOT"
    --env "HWS_WORKTREE_ROOT=$WS_WORKTREE_ROOT"
    --focus
  )
  herdr plugin pane open "${pane_args[@]}" >/dev/null
}

_ws_worktree_rows() {
  _ws_resolve_project_context || return
  cd "$WS_PROJECT_ROOT" || return
  _h_git_worktree_paths | while IFS= read -r wt_path; do
    [[ -d "$wt_path" ]] || continue
    printf '%s\t%s\n' "$(_h_worktree_label "$wt_path")" "$wt_path"
  done
}

_ws_worktree_rows_detailed() {
  _ws_resolve_project_context || return
  cd "$WS_PROJECT_ROOT" || return
  _h_git_worktree_paths | while IFS= read -r wt_path; do
    [[ -d "$wt_path" ]] || continue
    local label branch dirty open workspace_id marker
    label="$(_h_worktree_label "$wt_path")"
    branch="$(git -C "$wt_path" branch --show-current 2>/dev/null || true)"
    [[ -n "$branch" ]] || branch="detached"
    if [[ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
      dirty="dirty"
    else
      dirty="clean"
    fi
    workspace_id="$(_ws_workspace_id_for_path "$wt_path")"
    if [[ -n "$workspace_id" ]]; then
      open="open"
      marker="●"
    else
      open="hidden"
      marker="○"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$marker" "$label" "$branch" "$dirty" "$open" "$wt_path"
  done
}
