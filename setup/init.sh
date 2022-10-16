#!/bin/sh

# Install Xcode Developer Tools
xcode-select --install

# Install TMUX Plugin Manager
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Install Homebrew
ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

# Installing Homebrew packages, Cask binaries and Mac App Store software
source ./brew.sh

# Installing Node.js
source ./nvm.sh

# Installing Python version manager
source ./python.sh

# Installing Lua packages
source ./lua.sh