source "${0:A:h}/lib/project-context.zsh" || exit 0

# Best-effort event hook: Herdr-native worktree creation/opening already owns
# the selected workspace. Only remove stale objects; never bulk-create siblings.
_ws_resolve_project_context || exit 0
cd "$WS_PROJECT_ROOT" || exit 0
source "$WS_DOTFILES/zsh/functions/hsyncworktrees" --prune-only >/dev/null 2>&1 || true
if ! source "$WS_DOTFILES/zsh/functions/htrimworkspaces" --auto; then
  echo "Warning: automatic Herdr workspace trim failed; leaving workspaces open." >&2
fi
