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

# Directory shortcuts
alias dotfiles="cd $HOME/Developer/dotfiles"
alias hellomateo="cd $HOME/Developer/hellomateo.git"
alias sbch="cd $HOME/Developer/supabase-cache-helpers.git"
alias pglsp="cd $HOME/Developer/postgres-language-server.git"
alias pgconductor="cd $HOME/Developer/postgres-conductor.git"

# Nix
alias ndc='nix develop -c'
alias update='nix flake update --flake ~/Developer/dotfiles'

# Tools
alias j='just'
alias week='date +%V'
alias timer='echo "Timer started. Stop with Ctrl-D." && date && time cat && date'
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"
alias explain='open $HOME/Developer/dotfiles/scripts/explain.html'

# AI helpers
alias oc='copen'
alias ocweb='copenweb'

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

# git-town (stacked PRs)
alias gt='git town'
