#!/bin/bash
set -e

echo "=== psteinroe dotfiles bootstrap ==="

# Install Xcode CLI tools (needed for git)
if ! xcode-select -p &>/dev/null; then
  echo "Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "Press enter after Xcode tools are installed..."
  read
fi

# Install Nix
if ! command -v nix &>/dev/null; then
  echo "Installing Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix | sh -s -- install

  # Source nix in current shell
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Clone dotfiles
DOTFILES="$HOME/.dotfiles"
if [ ! -d "$DOTFILES" ]; then
  echo "Cloning dotfiles..."
  git clone git@github.com:psteinroe/dotfiles.git "$DOTFILES"
fi

cd "$DOTFILES"

# First run of nix-darwin (bootstraps itself)
echo "Building system configuration..."
nix run nix-darwin -- switch --flake .

echo ""
echo "=== Done! ==="
echo "Your system is configured. Restart your terminal."
echo ""
echo "Future updates: darwin-rebuild switch --flake ~/.dotfiles"
