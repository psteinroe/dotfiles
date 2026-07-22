# ZSH
alias reload="source $HOME/.zshrc"

# Navigation
alias ...='cd ../..'
alias ..='cd ..'
alias cd..='cd ..'
alias ls='eza -a -1 --icons'
alias mkdir='mkdir -p'

# Vim
alias vim='nvim'
alias v='nvim'

# Project shortcuts open Herdr sessions. Pass an optional worktree/branch/PR.
dotfiles() { hdev dotfiles "$@"; }
rdotfiles() { rdev dotfiles "$@"; }

hellomateo() { hdev hellomateo "$@"; }
rhellomateo() { rdev hellomateo "$@"; }

sbch() { hdev supabase-cache-helpers "$@"; }
rsbch() { rdev supabase-cache-helpers "$@"; }

pgls() { hdev postgres-language-server "$@"; }
pglsp() { pgls "$@"; }
rpgls() { rdev postgres-language-server "$@"; }
rpglsp() { rpgls "$@"; }

pgconductor() { hdev postgres-conductor "$@"; }
rpgconductor() { rdev postgres-conductor "$@"; }

pgstream() { hdev postgres-stream "$@"; }
rpgstream() { rdev postgres-stream "$@"; }

hpgstream() { hdev postgres-steam-getmateo "$@"; }
rhpgstream() { rdev postgres-steam-getmateo "$@"; }

toolshed() { hdev toolshed "$@"; }
rtoolshed() { rdev toolshed "$@"; }

# Nix
alias ndc='nix develop -c'
update() {
  local nix_config="${NIX_CONFIG:-}"

  if command -v gh >/dev/null 2>&1; then
    local github_token
    github_token="$(gh auth token 2>/dev/null || true)"
    if [[ -n "$github_token" ]]; then
      nix_config="access-tokens = github.com=$github_token${nix_config:+$'\n'$nix_config}"
    fi
  fi

  NIX_CONFIG="$nix_config" nix flake update --flake ~/Developer/dotfiles "$@"
}

# Tools
alias j='just'
alias week='date +%V'
alias timer='echo "Timer started. Stop with Ctrl-D." && date && time cat && date'
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"
alias explain='open $HOME/Developer/dotfiles/scripts/explain.html'

# pnpm
alias pn="pnpm"
alias pnr="pnpm run"

# Atuin
alias ah='atuin history list'
alias as='atuin search'
alias ast='atuin stats'
alias asd='atuin search --cwd .'
alias asw='atuin search --workspace'

# git
gc() { git commit -m "${1:-progress}"; }
gca() { git add -A && git commit -m "${1:-progress}"; }
alias gp='git push'
alias gl='git pull'
alias gs='git status'
gpd() { gh pr diff "$@" --color=never | diffnav; }
alias review='tuicr'
