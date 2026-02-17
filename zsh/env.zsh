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

# OpenCode shared server auth from keychain
export OPENCODE_SERVER_PASSWORD=$(keychain-environment-variable OPENCODE_SERVER_PASSWORD 2>/dev/null || echo "")
