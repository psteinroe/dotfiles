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

# git-town (stacked PRs)
alias gt='git town'
# Quick PR: commits "initial", pushes, opens PR editor
# Usage: gpr [-n]
#   gpr    = commit to current branch + push + create PR
#   gpr -n = create new random branch + commit + push + create PR
gpr() {
  if [ -z "$(git status --porcelain)" ]; then
    echo "No changes to commit"
    return 1
  fi

  if [ "$1" = "-n" ]; then
    # Create new branch with random name
    local adj=(quick bright calm cool dark fast free gold green happy keen loud mint neat pale pink pure red safe slim soft warm wild)
    local noun=(ant bear bird bolt cave crow dawn deer dove duck fern fish frog hawk iris jade lake leaf lion lynx moon moth oak owl pine pond rain rock rose sage snow star swan tide tree vine wave wolf)
    local branch="${adj[$RANDOM % ${#adj[@]} + 1]}-${noun[$RANDOM % ${#noun[@]} + 1]}"
    git add -A && git town hack "$branch" -c -m "initial" && gh pr create -e
  else
    # Commit to current branch
    git add -A && git commit -m "initial" && git push && gh pr create -e
  fi
}
