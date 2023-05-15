#!/bin/sh

# Install Xcode Developer Tools
xcode-select --install

# Install all available updates
sudo softwareupdate -i -a

# Install Rosetta 2
softwareupdate --install-rosetta --agree-to-license

# Install TMUX Plugin Manager
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Install Homebrew
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Load Homebrew
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Installing Homebrew packages, Cask binaries and Mac App Store software
cd "$parent_path"
source ./brew.sh

# Installing Node.js
cd "$parent_path"
source ./nvm.sh

# Installing Global Dependencies
cd "$parent_path"
source ./pnpm.sh

# Installing Python version manager
cd "$parent_path"
source ./python.sh

# Installing Lua packages
cd "$parent_path"
source ./lua.sh

# Installing Rust packages
cd "$parent_path"
source ./rust.sh

# Installing Neovim
cd "$parent_path"
source ./neovim.sh
