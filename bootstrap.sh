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

# Generate SSH key if missing
if [[ ! -f ~/.ssh/id_ed25519 ]]; then
  echo "Generating SSH key..."
  mkdir -p ~/.ssh
  ssh-keygen -t ed25519 -C "philipp@steinroetter.com" -N "" -f ~/.ssh/id_ed25519
fi

# Install Nix
if ! command -v nix &>/dev/null; then
  echo "Installing Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix | sh -s -- install

  # Source nix in current shell
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Setup GitHub auth and SSH keys (use nix run since gh not installed yet)
mkdir -p ~/.config/gh
if ! nix run nixpkgs#gh -- auth status &>/dev/null 2>&1; then
  echo "Authenticating with GitHub..."
  nix run nixpkgs#gh -- auth login -p ssh -w

  echo "Adding SSH key to GitHub..."
  nix run nixpkgs#gh -- ssh-key add ~/.ssh/id_ed25519.pub --type authentication --title "$(hostname)"
  nix run nixpkgs#gh -- ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "$(hostname) signing"
fi

# Clone or update dotfiles
DOTFILES="$HOME/Developer/dotfiles"
if [ ! -d "$DOTFILES" ]; then
  echo "Cloning dotfiles..."
  mkdir -p "$HOME/Developer"
  git clone git@github.com:psteinroe/dotfiles.git "$DOTFILES"
else
  echo "Updating dotfiles..."
  git -C "$DOTFILES" pull
fi

# First run of nix-darwin (bootstraps itself)
echo "Building system configuration..."
sudo HOME="$HOME" nix run nix-darwin -- switch --flake "$DOTFILES#psteinroe"

echo ""
echo "=== Done! ==="
echo "Your system is configured. Restart your terminal."
echo ""
echo "Future updates: darwin-rebuild switch --flake ~/Developer/dotfiles"
