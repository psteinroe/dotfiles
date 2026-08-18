#!/usr/bin/env zsh
set -u

plugin_dir=${0:A:h}
dotfiles=${DOTFILES_DIR:-${plugin_dir:h:h:h}}
set --
source "$dotfiles/zsh/functions/pireload"
