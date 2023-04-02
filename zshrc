# *** *** Configuration *** ***
CASE_SENSITIVE="true"          # Case-sensitive completion
DISABLE_AUTO_TITLE="true"      # Disable auto-setting terminal title
COMPLETION_WAITING_DOTS="true" # Red dots while waiting for completion

# Autosuggest Highlighting
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=7,bg=bold,underline"

export KEYTIMEOUT=1
export RIPGREP_CONFIG_PATH=$HOME/.ripgreprc
export GIT_EDITOR=nvim
export EDITOR=nvim

# Fish shell like syntax highlighting for zsh
source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR="$(brew --prefix)/share/zsh-syntax-highlighting/highlighters"

# Base16 Shell
source ~/.config/base16-shell/base16-shell.plugin.zsh

# FD
FD_OPTIONS="--follow --exclude .git --exclude node_modules"

export FZF_DEFAULT_COMMAND="git ls-files --cached --others --exclude-standard | fd --hidden --type f --type l $FD_OPTIONS"
export FZF_DEFAULT_OPTS='--no-height'

export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers {}' --bind shift-up:preview-page-up,shift-down:preview-page-down"

export FZF_ALT_C_COMMAND="fd --type d $FD_OPTIONS --color=never --hidden"
export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -50'"

export ZSH_CACHE_DIR=~/.zsh_cache

# rbenv
export RBENV_ROOT="$HOME/.rbenv/"

# nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
source $(brew --prefix nvm)/nvm.sh

# PNPM
export PNPM_HOME="/Users/psteinroe/Library/pnpm"
export PATH="$PNPM_HOME:$PATH"

# neovim managed by bob
export PATH="$HOME/Library/Application Support/neovim/bin:$PATH"

# Rancher
export PATH="$HOME/.rd/bin:$PATH"

# Rust
export PATH="$HOME/.cargo/bin:$PATH"

# Ruby
export PATH="/usr/local/opt/ruby/bin:$PATH"

# Pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init --path)"
eval "$(pyenv virtualenv-init -)"

# Man
export MANPATH="/usr/local/man:$MANPATH"

# Bat
export BAT_PAGER="less -R"

# Starship
eval "$(starship init zsh)"

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


# *** *** Functions *** ***

# Get OS X Software Updates, Homebrew, pnpm, and their installed packages
function update () {
  brew update && brew outdated && brew upgrade && brew cleanup
  pnpm -g update --latest
  nvim -c 'autocmd User PackerComplete quitall' -c 'PackerSync'
  nvim +Mason +15sleep +qall
  sudo softwareupdate -i -a
}

# Open the Pull Request URL for your current directory's branch (base branch defaults to main)
function openpr() {
  github_url=`git remote -v | awk '/fetch/{print $2}' | sed -Ee 's#(git@|git://)#https://#' -e 's@com:@com/@' -e 's%\.git$%%' | awk '/github/'`;
  branch_name=`git symbolic-ref HEAD | cut -d"/" -f 3,4`;
  pr_url=$github_url"/compare/dev..."$branch_name
  open $pr_url;
}

# Run git push and then immediately open the Pull Request URL
function gpr() {
  git push origin HEAD

  if [ $? -eq 0 ]; then
    openpr
  else
    echo 'failed to push commits and open a pull request.';
  fi
}

# Resets git by checking out the main branch and removing all merged branches but prod|staging|dev|main
function rg() {
  git checkout "$(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5)"
  git pull
  git branch --merged | egrep -v \"(^\\*|prod|staging|dev|main)\" | xargs git branch -d
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

autoload -Uz compinit && compinit

# *** *** Plugins *** ***

# Load Antidote plugin manager
source $(brew --prefix)/opt/antidote/share/antidote/antidote.zsh

# initialize plugins statically with ${ZDOTDIR:-~}/.zsh_plugins.txt
antidote load $HOME/.dotfiles/zsh_plugins.txt

# Additional zsh plugins
fpath=(~/.zsh.d/ $fpath)

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

# Tmuxinator
alias mux="tmuxinator"

# Bat
alias cat="bat"

# Directory shortcuts
alias dotfiles="cd $HOME/.dotfiles"
alias hellomateo="cd $HOME/Developer/hellomateo"
alias sbch="cd $HOME/Developer/supabase-cache-helpers"

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

# tabtab source for pnpm package
# uninstall by removing these lines
[[ -f ~/.config/tabtab/zsh/__tabtab.zsh ]] && . ~/.config/tabtab/zsh/__tabtab.zsh || true

