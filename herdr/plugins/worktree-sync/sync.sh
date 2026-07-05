source "${0:A:h}/lib/project-context.zsh" || exit 1
_ws_resolve_project_context || exit 1
cd "$WS_PROJECT_ROOT" || exit 1
source "$WS_DOTFILES/zsh/functions/hsyncworktrees" --prune
