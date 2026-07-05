source "${0:A:h}/lib/project-context.zsh" || exit 0

# Best-effort event hook: when Herdr-native worktree operations occur, make sure
# the workspace set is still synced to this repo's established worktree layout.
_ws_resolve_project_context || exit 0
cd "$WS_PROJECT_ROOT" || exit 0
source "$WS_DOTFILES/zsh/functions/hsyncworktrees" --prune >/dev/null 2>&1 || true
