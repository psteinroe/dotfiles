source "$(brew --prefix)/share/antigen/antigen.zsh"

# Load the oh-my-zsh library.
antigen use oh-my-zsh plugins/gh plugins/per-directory-history plugins/git-auto-fetch plugins/tmux

# Autocomplete bundle.
# antigen bundle marlonrichert/zsh-autocomplete@main

# Autosuggestions bundle.
antigen bundle zsh-users/zsh-autosuggestions

# Syntax highlighting bundle.
antigen bundle zsh-users/zsh-syntax-highlighting

# Vi mode
antigen bundle jeffreytse/zsh-vi-mode

antigen theme sbugzu/gruvbox-zsh

# Tell Antigen that you're done.
antigen apply

# Zoxide
eval "$(zoxide init zsh)"

CASE_SENSITIVE="true"          # Case-sensitive completion
DISABLE_AUTO_TITLE="true"      # Disable auto-setting terminal title

# Auto-update behavior
zstyle ':omz:update' mode auto      # update automatically without asking

HIST_STAMPS="yyyy-mm-dd"

# Autosuggest Highlighting
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=7,bg=bold,underline"

export KEYTIMEOUT=1
export GIT_EDITOR=nvim
export EDITOR=nvim

# Base16 Shell
source ~/.config/base16-shell/base16-shell.plugin.zsh

# Autocomplete
# source ~/.antigen/bundles/marlonrichert/zsh-autocomplete-main/zsh-autocomplete.plugin.zsh

# Start each command line in history search mode
# zstyle ':autocomplete:*' default-context history-incremental-search-backward

# tumxifier
export PATH="$HOME/.tmux/plugins/tmuxifier/bin:$PATH"
export TMUXIFIER_LAYOUT_PATH="$HOME/.dotfiles/tmux-layouts"

# FD
FD_OPTIONS="--follow --exclude .git --exclude node_modules"

# FZF
export FZF_DEFAULT_COMMAND="git ls-files --cached --others --exclude-standard | fd --hidden --type f --type l $FD_OPTIONS"
export FZF_DEFAULT_OPTS='--no-height'

export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers {}' --bind shift-up:preview-page-up,shift-down:preview-page-down"

export FZF_ALT_C_COMMAND="fd --type d $FD_OPTIONS --color=never --hidden"
export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -50'"

# ripgrep
export RIPGREP_CONFIG_PATH=$HOME/.ripgreprc

# rbenv
export RBENV_ROOT="$HOME/.rbenv/"

# nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
source $(brew --prefix nvm)/nvm.sh

# PNPM
export PNPM_HOME="/Users/psteinroe/Library/pnpm"
export PATH="$PNPM_HOME:$PATH"

# neovim managed by bob
export PATH="$HOME/.local/share/bob/nvim-bin:$PATH"

# Rust
export PATH="$HOME/.cargo/bin:$PATH"

# Ruby
export PATH="/usr/local/opt/ruby/bin:$PATH"

# Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"

# Android platform tools
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"

# postgres_lsp debug build
export PATH="$HOME/Developer/postgres_lsp/target/debug:$PATH"

# Starship
eval "$(starship init zsh)"

export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools

# Use: keychain-environment-variable SECRET_ENV_VAR
function keychain-environment-variable () {
    security find-generic-password -w -a ${USER} -D "environment variable" -s "${1}"
}
# Use: set-keychain-environment-variable SECRET_ENV_VAR
#   provide: super_secret_key_abc123
function set-keychain-environment-variable () {
    [ -n "$1" ] || print "Missing environment variable name"
# Note: if using bash, use `-p` to indicate a prompt string, rather than the leading `?`
read -s "?Enter Value for ${1}: " secret
    ( [ -n "$1" ] && [ -n "$secret" ] ) || return 1
    security add-generic-password -U -a ${USER} -D "environment variable" -s "${1}" -w "${secret}"
}

export ANTHROPIC_API_KEY=$(keychain-environment-variable ANTHROPIC_API_KEY);

# FZF
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Path
path=(
  $HOME/.dotfiles/bin
  $HOME/.local/bin
  /usr/local/sbin
  $path
)

# Bindkey
bindkey -v
bindkey -M viins '^r' fzf-history-widget # (r)everse history search
bindkey -M viins '^f' fzf-file-widget    # (f)ile / (t)
bindkey -M viins '^z' fzf-cd-widget      # (z) jump
# bindkey              '^I'         menu-complete
# bindkey "$terminfo[kcbt]" reverse-menu-complet

# *** *** Functions *** ***

# Update all Wallpapers
function set_wallpaper() {
    osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"/Users/psteinroe/.dotfiles/media/wallpaper.jpg\" as POSIX file"
}

# Auto change the nvm version based on a .nvmrc file based on the current directory.
# See https://github.com/creationix/nvm/issues/110#issuecomment-190125863
autoload -U add-zsh-hook
load-nvmrc() {
  if [[ -f .nvmrc && -r .nvmrc ]]; then
    nvm use
  fi
}
add-zsh-hook chpwd load-nvmrc
load-nvmrc

# *** *** Aliases *** ***

# ZSH
alias zshconfig="vim $HOME/.zshrc"
alias reload="source $HOME/.zshrc"

# Folders
alias ...='cd ../..'
alias ..='cd ..'
alias cd..='cd ..'
alias ll='exa -l -g --icons'
alias lla='ll -a'
alias mkdir='mkdir -p'

# Vim
alias v='vim'

if type nvim > /dev/null 2>&1; then
  alias vim='nvim'
fi

# Directory shortcuts
alias dotfiles="cd $HOME/.dotfiles"
alias hellomateo="cd $HOME/Developer/hellomateo"
alias sbch="cd $HOME/Developer/supabase-cache-helpers"
alias pg_lsp="cd $HOME/Developer/postgres_lsp"

# Get week number
alias week='date +%V'

# Stopwatch
alias timer='echo "Timer started. Stop with Ctrl-D." && date && time cat && date'

# Recursively delete `.DS_Store` files
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"

# Empty the Trash on all mounted volumes and the main HDD
# Also, clear Apple’s System Logs to improve shell startup speed
alias emptytrash="sudo rm -rfv /Volumes/*/.Trashes; sudo rm -rfv ~/.Trash; sudo rm -rfv /private/var/log/asl/*.asl"

# Supabase CLI
alias sb="supabase"

# Git
alias gc="git commit -m"
alias gp="git push"

# pnpm
alias pn="pnpm"
alias pnr="pnpm run"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
