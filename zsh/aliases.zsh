# ZSH
alias reload="source $HOME/.zshrc"

# Navigation
alias ...='cd ../..'
alias ..='cd ..'
alias cd..='cd ..'
alias ll='eza -l -g --icons'
alias lla='ll -a'
alias mkdir='mkdir -p'

# Vim
alias vim='nvim'
alias v='nvim'

# Directory shortcuts
alias dotfiles="cd $HOME/Developer/dotfiles"
alias hellomateo="cd $HOME/Developer/hellomateo.git"
alias sbch="cd $HOME/Developer/supabase-cache-helpers"
alias pglsp="cd $HOME/Developer/postgres-language-server.git"
alias pgconductor="cd $HOME/Developer/pgconductor"

# Tools
alias j='just'
alias week='date +%V'
alias timer='echo "Timer started. Stop with Ctrl-D." && date && time cat && date'
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"
alias sb="supabase"
alias explain='open $HOME/Developer/dotfiles/scripts/explain.html'

# Git
alias gc="git commit -m"
alias gp="git push"

# pnpm
alias pn="pnpm"
alias pnr="pnpm run"

# Atuin
alias ah='atuin history list'
alias as='atuin search'
alias ast='atuin stats'
alias asd='atuin search --cwd .'
alias asw='atuin search --workspace'

# jj (Jujutsu) - basics
alias jjs='jj status'
alias jjd='jj diff'
alias jjl='jj log -r "trunk()..@"'
alias jjla='jj log'

# jj stack navigation
alias jjn='jj next --edit'
alias jjp='jj prev --edit'
alias jje='jj edit'

# jj creating/modifying stack
alias jjnew='jj new'
alias jjnewb='jj new -B'
alias jjc='jj commit -m'
alias jjb='jj bookmark create'
alias jjbm='jj bookmark move'

# jj rebasing - trunk() auto-detects main/master/etc
alias jjr='jj rebase -d "trunk()"'
alias jjf='jj git fetch --all-remotes'

# jj-ryu (PR submission workflow)
alias jjstack='ryu'
alias jjtrack='ryu track'
alias jjuntrack='ryu untrack'
alias jjsubmit='ryu submit'
alias jjsync='ryu sync'
