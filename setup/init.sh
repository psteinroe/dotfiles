#!/bin/sh

# Keep screen on
caffeinate -t 3600 &

# Install all available updates
sudo softwareupdate -i -a

# Install Xcode Developer Tools
xcode-select --install

# Install Rosetta 2
softwareupdate --install-rosetta --agree-to-license

# Install TMUX Plugin Manager
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Install Homebrew
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Load Homebrew
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

source ~/.zshrc

# Set Wallpaper
set_wallpaper

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Installing Homebrew packages, Cask binaries and Mac App Store software
cd "$parent_path"
source ./brew.sh

# Accepts license
sudo xcodebuild -license

source ~/.zshrc

# Installing Node.js
cd "$parent_path"
source ./nvm.sh

source ~/.zshrc

# Installing Global Dependencies
cd "$parent_path"
source ./pnpm.sh

source ~/.zshrc

# Installing Python version manager
cd "$parent_path"
source ./python.sh

source ~/.zshrc

# Installing elixir packages
cd "$parent_path"
source ./elixir.sh

source ~/.zshrc

# Installing Lua packages
cd "$parent_path"
source ./lua.sh

source ~/.zshrc

# Installing Rust packages
cd "$parent_path"
source ./rust.sh

source ~/.zshrc

# Installing Neovim
cd "$parent_path"
source ./neovim.sh

source ~/.zshrc

# Setup zsh
cd "$parent_path"
source ./zsh.sh

source ~/.zshrc

# Setup Java
cd "$parent_path"
source ./java.sh

source ~/.zshrc

# Setup Dock
cd "$parent_path"
source ./dock.sh

# Install nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --determinate
