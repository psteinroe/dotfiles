source "${0:A:h}/lib/project-context.zsh" || exit 1
_ws_resolve_project_context || exit 1

_ws_close_self() {
  [[ -n "${HERDR_PANE_ID:-}" ]] && herdr pane close "$HERDR_PANE_ID" >/dev/null 2>&1 || true
}

_ws_pause() {
  echo
  echo "Press enter..."
  read _
}

_ws_print_table() {
  local rows="$1"
  printf '  %-1s  %-28s %-28s %-7s %-7s %s\n' "" "WORKTREE" "BRANCH" "STATUS" "HERDR" "PATH"
  print -r -- "$rows" | while IFS=$'\t' read -r marker label branch dirty open wt_path; do
    [[ -n "$label" ]] || continue
    printf '  %-1s  %-28s %-28s %-7s %-7s %s\n' "$marker" "$label" "$branch" "$dirty" "$open" "$wt_path"
  done
}

_ws_pick_worktree() {
  local rows selected idx count line
  rows="$(_ws_worktree_rows_detailed)" || return
  if [[ -z "$rows" ]]; then
    echo "No worktrees found for $WS_PROJECT_NAME." >&2
    return 1
  fi

  # Prefer the simple numbered menu inside Herdr overlay panes. fzf can briefly
  # flash and exit in some remote/mobile terminal combinations, which makes the
  # Shift+O shortcut look broken. Keep fzf available as an explicit opt-in for
  # local debugging with HWS_USE_FZF=1.
  if [[ "${HWS_USE_FZF:-0}" == 1 ]] && command -v fzf >/dev/null 2>&1; then
    selected=$(print -r -- "$rows" | fzf \
      --prompt="$WS_PROJECT_NAME worktree> " \
      --height=85% \
      --reverse \
      --delimiter=$'\t' \
      --with-nth=1,2,3,4,5,6 \
      --header=$'● open in Herdr / ○ hidden | columns: marker worktree branch dirty herdr path' \
      --preview='wt_path=$(printf %s {} | awk -F "\t" "{print \$6}"); git -C "$wt_path" status --short --branch 2>/dev/null; printf "\\nRecent commits:\\n"; git -C "$wt_path" log --oneline -5 2>/dev/null' \
      --preview-window=down,45%) || return 1
    print -r -- "${selected##*$'\t'}"
    return 0
  fi

  echo "Worktrees for $WS_PROJECT_NAME:"
  idx=1
  print -r -- "$rows" | while IFS=$'\t' read -r marker label branch dirty open wt_path; do
    printf '  %2d) %s %-26s %-24s %-7s %-7s %s\n' "$idx" "$marker" "$label" "$branch" "$dirty" "$open" "$wt_path" >&2
    idx=$((idx + 1))
  done
  count=$(print -r -- "$rows" | wc -l | tr -d ' ')
  printf 'Open number: ' >&2
  read idx
  [[ "$idx" == <-> && "$idx" -ge 1 && "$idx" -le "$count" ]] || return 1
  line=$(print -r -- "$rows" | sed -n "${idx}p")
  print -r -- "${line##*$'\t'}"
}

_ws_open_worktree() {
  local wt_path label
  wt_path="$(_ws_pick_worktree)" || return
  label="$(_h_worktree_label "$wt_path")"
  _ws_focus_or_create_workspace "$wt_path" "$label"
  _ws_close_self
}

_ws_create_worktree() {
  local requested
  echo "Project: $WS_PROJECT_NAME"
  echo "Current worktree: $WS_PROJECT_CWD"
  echo
  printf 'Branch/worktree/PR to create or open: '
  read requested
  [[ -n "$requested" ]] || return 1
  cd "$WS_PROJECT_ROOT" || return
  source "$WS_DOTFILES/zsh/functions/hwtcreate" "$requested"
  _ws_close_self
}

_ws_sync_worktrees() {
  cd "$WS_PROJECT_ROOT" || return
  source "$WS_DOTFILES/zsh/functions/hsyncworktrees" --prune
}

_ws_clean_worktrees() {
  local cleanup_cwd="$WS_PROJECT_CWD"
  local cleanup_status

  # Match direct wtclean behavior by running from the workspace that opened the
  # overlay. This keeps the hosting worktree out of the removal candidates and
  # prevents cleanup from closing the workspace that owns its own pane.
  [[ -d "$cleanup_cwd" ]] || cleanup_cwd="$WS_PROJECT_ROOT"
  cd "$cleanup_cwd" || return
  source "$WS_DOTFILES/zsh/functions/wtclean"
  cleanup_status=$?
  _ws_pause
  _ws_close_self
  return "$cleanup_status"
}

_ws_bootstrap_workspace() {
  source "$WS_PLUGIN_DIR/bootstrap.sh"
  _ws_pause
  _ws_close_self
}

_ws_hide_workspace() {
  source "$WS_PLUGIN_DIR/hide.sh"
}

case "${HWS_MODE:-manager}" in
  open)
    _ws_open_worktree
    exit $?
    ;;
  create)
    _ws_create_worktree
    exit $?
    ;;
  clean)
    _ws_clean_worktrees
    exit $?
    ;;
esac

while true; do
  rows="$(_ws_worktree_rows_detailed)"
  clear 2>/dev/null || true
  echo "Worktree Manager — $WS_PROJECT_NAME"
  echo "Project root:  $WS_PROJECT_ROOT"
  echo "Worktree root: $WS_WORKTREE_ROOT"
  echo "Current cwd:   $WS_PROJECT_CWD"
  echo
  _ws_print_table "$rows"
  echo
  echo "Actions:"
  echo "  o  open/focus worktree       c  create/ensure worktree"
  echo "  s  sync + prune stale        b  bootstrap panes"
  echo "  x  hide current workspace    k  clean merged/closed worktrees"
  echo "  q  quit"
  echo
  printf '> '
  read action
  case "$action" in
    o) _ws_open_worktree ;;
    c) _ws_create_worktree ;;
    s) _ws_sync_worktrees; _ws_pause ;;
    b) _ws_bootstrap_workspace ;;
    x) _ws_hide_workspace ;;
    k) _ws_clean_worktrees; exit $? ;;
    q|'') _ws_close_self; exit 0 ;;
  esac
done
