source "$(brew --prefix)/share/antigen/antigen.zsh"

# Load the oh-my-zsh library.
antigen use oh-my-zsh plugins/gh plugins/git-auto-fetch plugins/tmux

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

# Configure autosuggestions to NOT use Tab by default
ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(expand-or-complete)

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
# Go
export PATH="$HOME/go/bin:$PATH"

# Ruby
export PATH="/usr/local/opt/ruby/bin:$PATH"

# Android SDK
export ANDROID_HOME="$HOME/Library/Android/sdk"

# Android platform tools
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"

# postgres_lsp debug build
export PATH="$HOME/Developer/postgres-language-server.git/main/target/debug:$PATH"

# Postgres Language Server Log Path
export PGT_LOG_PATH="$HOME/Library/Caches/dev.supabase-community.pgt/pgt-logs"

# Starship
eval "$(starship init zsh)"

# Atuin - magical shell history
eval "$(atuin init zsh)"

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
# Atuin handles Ctrl-R by default, use Alt-R for FZF as fallback
bindkey -M viins '^[r' fzf-history-widget # Alt-R for FZF history
bindkey -M viins '^f' fzf-file-widget    # (f)ile / (t)
bindkey -M viins '^z' fzf-cd-widget      # (z) jump
# Tab accepts autosuggestion, Shift+Tab opens completion menu
bindkey -M viins '^I' autosuggest-accept        # Tab accepts suggestion
bindkey -M viins '^[[Z' expand-or-complete      # Shift+Tab for completion menu
# Right arrow: complete at end of line, otherwise move cursor
bindkey '^[OC' right-arrow-or-complete   # Right arrow
bindkey '^[[C' right-arrow-or-complete   # Right arrow (alternate sequence)

# *** *** Functions *** ***

# Right arrow: show completion menu if at end of line, otherwise move cursor
function right-arrow-or-complete() {
    if [[ $CURSOR -eq ${#BUFFER} ]]; then
        zle list-choices
        zle menu-complete
    else
        zle forward-char
    fi
}
zle -N right-arrow-or-complete

# Update all Wallpapers
function set_wallpaper() {
    osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"/Users/psteinroe/.dotfiles/media/wallpaper.jpg\" as POSIX file"
}

function explain() {
    open -a "Safari" "$HOME/.dotfiles/explain.html"
}

# ffmpeg -i in.mov -pix_fmt rgb8 -r 10 output.gif && gifsicle -O3 output.gif -o output.gif

# Convert video to optimized GIF
function video_to_gif() {
  if [ -z "$1" ]; then
    echo "Usage: video_to_gif input_file.mov [output_file.gif] [framerate]"
    echo "  Default output file will be input_file.gif"
    echo "  Default framerate is 10"
    return 1
  fi

  local input_file="$1"
  local output_file="${2:-${input_file%.*}.gif}"
  local framerate="${3:-10}"

  echo "Converting $input_file to $output_file with framerate $framerate..."
  ffmpeg -i "$input_file" -pix_fmt rgb8 -r "$framerate" "$output_file" && \
  gifsicle -O3 "$output_file" -o "$output_file" && \
  echo "Conversion complete: $output_file"
}

tm() {
    if command -v fzf >/dev/null 2>&1; then
        local selection
        selection=$(tmuxifier list | grep "^ - " | sed 's/^ - //' | while read -r session; do
            if tmux has-session -t "$session" 2>/dev/null; then
                echo "$session (active)"
            else
                echo "$session"
            fi
        done | fzf --height 40% --reverse)

        if [[ -n "$selection" ]]; then
            # Extract session name (remove status if present)
            local session_name
            session_name=$(echo "$selection" | sed 's/ (active)$//')

            # Set Ghostty tab title explicitly (requires Ghostty CLI)
            if command -v ghostty >/dev/null 2>&1; then
                ghostty title "tmux: $session_name"
            fi

            # Track session switch in Atuin history
            atuin history start "tmuxifier load-session $session_name" || true
            tmuxifier load-session "$session_name"
        fi
    else
        echo "Available tmuxifier sessions:"
        tmuxifier list | grep "^ - " | sed 's/^ - //' | while read session; do
            if tmux has-session -t "$session" 2>/dev/null; then
                echo "  $session (active)"
            else
                echo "  $session"
            fi
        done
    fi
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

wtlist() {
  git worktree list
}

# Git worktree helper - lists worktrees and optionally cleans up merged PRs
function wtclean() {
  git worktree list

  if ! command -v gh >/dev/null 2>&1; then
    echo "\nGitHub CLI (gh) required for safe cleanup."
    return 1
  fi

  echo "\nChecking PR status..."
  local cleanup_candidates=()
  local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  local temp_file=$(mktemp)

  git worktree list --porcelain | grep '^worktree' | cut -d' ' -f2- | while read worktree_path; do
    if [ "$worktree_path" != "$repo_root" ] && [ "$worktree_path" != "$(dirname "$repo_root")/$(basename "$repo_root")" ]; then
      local branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null)
      if [ -n "$branch" ]; then
        local pr_state=$(gh pr view "$branch" --json state -q '.state' 2>/dev/null || echo "")
        case "$pr_state" in
          "MERGED")
            echo "Merged: $branch"
            echo "$worktree_path:$branch" >> "$temp_file"
            ;;
          "CLOSED")
            echo "Closed: $branch"
            echo "$worktree_path:$branch" >> "$temp_file"
            ;;
          "OPEN")
            echo "Active: $branch"
            ;;
          "")
            echo "No PR: $branch"
            ;;
        esac
      fi
    fi
  done

  if [ ! -s "$temp_file" ]; then
    echo "\nNo merged/closed PRs found."
    rm -f "$temp_file"
    return 0
  fi

  echo "\nRemovable worktrees:"
  while IFS=: read -r worktree_path branch; do
    echo "  $branch"
    cleanup_candidates+=("$worktree_path:$branch")
  done < "$temp_file"

  echo -n "\nRemove these? (y/N): "
  read response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    while IFS=: read -r worktree_path branch; do
      echo "Removing $branch..."
      git worktree remove "$worktree_path" --force
    done < "$temp_file"
    echo "\nDone."
  else
    echo "Cancelled."
  fi

  rm -f "$temp_file"
}

# Git worktree helper - creates a new worktree and navigates to it
function wtcreate() {
  if [ -z "$1" ]; then
    echo "Usage: gwt <branch-name>"
    echo "Creates a git worktree, navigates to it, and runs package manager install/check"
    return 1
  fi

  local branch_name="$1"

  # Get the main repository root from worktree list
  local repo_root=$(git worktree list --porcelain | grep "^worktree" | head -1 | cut -d' ' -f2-)
  if [ -z "$repo_root" ]; then
    echo "Not in a git repository"
    return 1
  fi

  # Fetch latest changes from remote
  echo "Fetching latest changes..."
  git fetch

  # Get the repository name
  local repo_name=$(basename "$repo_root")

  # Create worktree path relative to the parent of the current worktree
  local worktree_parent=$(dirname "$repo_root")
  # Check if repo name already ends with .git
  if [[ "$repo_name" == *.git ]]; then
    local worktree_path="$worktree_parent/$repo_name/$branch_name"
  else
    local worktree_path="$worktree_parent/$repo_name.git/$branch_name"
  fi

  # Create the worktree
  if git worktree add "$worktree_path" -b "$branch_name"; then
    echo "Created worktree at: $worktree_path"

    # Navigate to the new worktree
    cd "$worktree_path"

    # Check for git submodules
    if [ -f ".gitmodules" ]; then
      echo "Found .gitmodules, updating submodules..."
      git submodule update --init --recursive
    fi

    # Check for different package managers and run appropriate commands
    if [ -f "pnpm-lock.yaml" ]; then
      echo "Found pnpm-lock.yaml, running pnpm install..."
      pnpm install
    fi

    if [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
      echo "Found bun lockfile, running bun install..."
      bun install
    fi

    # Check for Cargo workspace
    if [ -f "Cargo.toml" ] && (grep -q "^\[workspace\]" "Cargo.toml" || [ -d "crates" ] || [ -d "packages" ]); then
      echo "Found Cargo workspace, running cargo check..."
      cargo check
    fi
  else
    echo "Failed to create worktree"
    return 1
  fi
}

# Claude Code with per-directory session persistence
ccode() {
    local session_file=".claude-session-id"
    local session_id

    # Ensure session file is always gitignored
    if [[ -f ".gitignore" ]]; then
        if ! grep -q "^\.claude-session-id$" .gitignore; then
            echo ".claude-session-id" >> .gitignore
        fi
    else
        # Create .gitignore if it doesn't exist
        echo ".claude-session-id" > .gitignore
    fi

    if [[ -f "$session_file" ]]; then
        # Use existing session ID for this directory
        session_id=$(cat "$session_file")
        echo "Resuming session in $(basename $(pwd)): $session_id"
        # Launch Claude with resume if session exists, fallback to new session on error
        if ! command claude --dangerously-skip-permissions --resume "$session_id"; then
            echo "Session resume failed, starting new session..."
            session_id=$(uuidgen)
            echo "$session_id" > "$session_file"
            command claude --dangerously-skip-permissions --session-id "$session_id"
        fi
    else
        # Generate new session ID and save it
        session_id=$(uuidgen)
        echo "$session_id" > "$session_file"
        echo "Starting new session in $(basename $(pwd)): $session_id"
        # Launch Claude with session-id for new sessions
        command claude --dangerously-skip-permissions --session-id "$session_id"
    fi
}

# Codex Code with per-directory session persistence
ccodex() {
    local session_file=".codex-session-id"
    local session_id
    local cwd_name="$(basename $(pwd))"

    # Ensure session file is always gitignored
    if [[ -f ".gitignore" ]]; then
        if ! grep -q "^\.codex-session-id$" .gitignore; then
            echo ".codex-session-id" >> .gitignore
        fi
    else
        # Create .gitignore if it doesn't exist
        echo ".codex-session-id" > .gitignore
    fi

    if [[ -f "$session_file" ]]; then
        session_id=$(cat "$session_file")
        echo "Resuming Codex session in ${cwd_name}: $session_id"
        if ! command codex resume --yolo "$session_id"; then
            echo "Session resume failed, starting new Codex session..."
            session_id=$(uuidgen)
            echo "$session_id" > "$session_file"
            command codex --yolo --session-id "$session_id"
        fi
    else
        session_id=$(uuidgen)
        echo "$session_id" > "$session_file"
        echo "Starting new Codex session in ${cwd_name}: $session_id"
        command codex --yolo --session-id "$session_id"
    fi
}

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
alias hellomateo="cd $HOME/Developer/hellomateo.git"
alias sbch="cd $HOME/Developer/supabase-cache-helpers"
alias pglsp="cd $HOME/Developer/postgres-language-server.git"
alias pgconductor="cd $HOME/Developer/pgconductor"
alias ninjascale="cd $HOME/Developer/otel-autoscaler"

# Just
alias j='just'

# Get week number
alias week='date +%V'

# Stopwatch
alias timer='echo "Timer started. Stop with Ctrl-D." && date && time cat && date'

# Recursively delete `.DS_Store` files
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"

# Empty the Trash on all mounted volumes and the main HDD
# Also, clear Apple's System Logs to improve shell startup speed
alias emptytrash="sudo rm -rfv /Volumes/*/.Trashes; sudo rm -rfv ~/.Trash; sudo rm -rfv /private/var/log/asl/*.asl"

# Supabase CLI
alias sb="supabase"

# Git
alias gc="git commit -m"
alias gp="git push"

# pnpm
alias pn="pnpm"
alias pnr="pnpm run"

# Atuin aliases
alias ah='atuin history list'                    # List recent commands
alias as='atuin search'                         # Search with UI
alias ast='atuin stats'                         # Usage statistics
alias asd='atuin search --cwd .'               # Search in current dir
alias asw='atuin search --workspace'            # Search in git workspace
alias zstats='atuin search --cmd "z " --limit 50 | sort | uniq -c | sort -nr'  # Zoxide usage stats

export PATH="/opt/homebrew/opt/libpq/bin:$PATH"


PROMPT_COMMAND='echo -en "\033]0;$(whoami)@$(hostname)|$(pwd|cut -d "/" -f 4-100)\a"'

# bun completions
[ -s "/Users/psteinroe/.bun/_bun" ] && source "/Users/psteinroe/.bun/_bun"
