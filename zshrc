# ============================================
# Environment Variables
# ============================================

export KEYTIMEOUT=1
export GIT_EDITOR=nvim
export EDITOR=nvim
export RIPGREP_CONFIG_PATH=$HOME/.ripgreprc

# FD options for FZF
FD_OPTIONS="--follow --exclude .git --exclude node_modules"

# FZF
export FZF_DEFAULT_COMMAND="git ls-files --cached --others --exclude-standard | fd --hidden --type f --type l $FD_OPTIONS"
export FZF_DEFAULT_OPTS='--no-height'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers {}' --bind shift-up:preview-page-up,shift-down:preview-page-down"
export FZF_ALT_C_COMMAND="fd --type d $FD_OPTIONS --color=never --hidden"
export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -50'"

# Postgres Language Server
export PGT_LOG_PATH="$HOME/Library/Caches/dev.supabase-community.pgt/pgt-logs"

# Anthropic API Key from keychain
export ANTHROPIC_API_KEY=$(keychain-environment-variable ANTHROPIC_API_KEY 2>/dev/null || echo "");

# ============================================
# PATH
# ============================================

path=(
  $HOME/Developer/dotfiles/bin
  $HOME/.local/bin
  $HOME/.cargo/bin                    # Rust
  $HOME/go/bin                        # Go
  $HOME/Library/pnpm                  # PNPM
  $HOME/Developer/postgres-language-server.git/main/target/debug  # PGT debug
  /opt/homebrew/opt/libpq/bin         # PostgreSQL tools
  /usr/local/sbin
  $path
)

# ============================================
# Zsh Options
# ============================================

CASE_SENSITIVE="true"
DISABLE_AUTO_TITLE="true"
HIST_STAMPS="yyyy-mm-dd"

# Autosuggest styling
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=7,bg=bold,underline"
ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(expand-or-complete)

# ============================================
# Key Bindings
# ============================================

bindkey -v

# Atuin handles Ctrl-R, use Alt-R for FZF as fallback
bindkey -M viins '^[r' fzf-history-widget
bindkey -M viins '^f' fzf-file-widget
bindkey -M viins '^z' fzf-cd-widget

# Tab accepts autosuggestion, Shift+Tab opens completion menu
bindkey -M viins '^I' autosuggest-accept
bindkey -M viins '^[[Z' expand-or-complete

# Right arrow completion
bindkey '^[OC' right-arrow-or-complete
bindkey '^[[C' right-arrow-or-complete

# ZLE widget for right arrow completion
function right-arrow-or-complete() {
  if [[ $CURSOR -eq ${#BUFFER} ]]; then
    zle list-choices
    zle menu-complete
  else
    zle forward-char
  fi
}
zle -N right-arrow-or-complete

# ============================================
# Aliases
# ============================================

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
alias v='vim'
type nvim > /dev/null 2>&1 && alias vim='nvim'

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

# ============================================
# Completions
# ============================================

[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"
