#!/bin/bash
set -e

DOTFILES="$HOME/Developer/dotfiles"

sudo HOME="$HOME" darwin-rebuild switch --flake "$DOTFILES#psteinroe"
