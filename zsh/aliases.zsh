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

# Clean up merged branches (detects main branch dynamically via gh)
gclean() {
  local main=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "main")
  local branches=$(git branch --merged "$main" | grep -v "^\\*" | grep -v "^  $main$" | grep -v "^  production$")
  [ -n "$branches" ] && echo "$branches" | xargs git branch -d || echo "No merged branches to clean"
}

# Reset to clean state: checkout main, pull, clean merged branches
greset() {
  local main=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "main")
  git checkout "$main" && git pull && gclean
}

# git-town (stacked PRs)
alias gt='git town'
# Quick PR: commits "initial", pushes, opens PR editor
# Usage: gpr [-a] [-n]
#   gpr       = commit (if changes) + push + create PR
#   gpr -a    = git add -A + commit (if changes) + push + create PR
#   gpr -n    = new random branch + commit (if changes) + push + create PR
#   gpr -a -n = git add -A + new branch + commit (if changes) + push + create PR
gpr() {
  local add_all=false new_branch=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a) add_all=true; shift ;;
      -n) new_branch=true; shift ;;
      *) shift ;;
    esac
  done

  $add_all && git add -A

  if $new_branch; then
    local main=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo "main")
    local adj=(quick bright calm cool dark fast free gold green happy keen loud mint neat pale pink pure red safe slim soft warm wild)
    local noun=(ant bear bird bolt cave crow dawn deer dove duck fern fish frog hawk iris jade lake leaf lion lynx moon moth oak owl pine pond rain rock rose sage snow star swan tide tree vine wave wolf)
    local branch="${adj[$RANDOM % ${#adj[@]} + 1]}-${noun[$RANDOM % ${#noun[@]} + 1]}"
    git checkout "$main" && git pull && git checkout -b "$branch"
    [ -n "$(git status --porcelain)" ] && git commit -m "initial"
    git push -u origin "$branch" && gh pr create -e
  else
    local branch=$(git branch --show-current)
    [ -n "$(git status --porcelain)" ] && git commit -m "initial"
    git push -u origin "$branch" && gh pr create -e
  fi
}
