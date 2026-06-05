#!/bin/bash

set -euo pipefail

echo "=== psteinroe dotfiles bootstrap ==="

die() {
  echo ""
  echo "ERROR: $1"
  echo ""
  exit 1
}

github_ssh_works() {
  local output

  output="$(ssh -o BatchMode=yes -T git@github.com 2>&1 || true)"
  echo "$output"

  echo "$output" | grep -q "successfully authenticated"
}

run_gh() {
  nix run nixpkgs#gh -- "$@"
}

# Install Xcode CLI tools, needed for git
if ! xcode-select -p &>/dev/null; then
  echo "Installing Xcode Command Line Tools..."
  xcode-select --install

  echo ""
  echo "Press enter after Xcode tools are installed..."
  read -r
fi

# Ensure ~/.ssh exists
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Generate SSH key if missing
if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
  echo "Generating SSH key..."
  ssh-keygen -t ed25519 \
    -C "philipp@steinroetter.com" \
    -N "" \
    -f "$HOME/.ssh/id_ed25519"
fi

[[ -f "$HOME/.ssh/id_ed25519.pub" ]] || die "Missing SSH public key: $HOME/.ssh/id_ed25519.pub"

chmod 600 "$HOME/.ssh/id_ed25519"
chmod 644 "$HOME/.ssh/id_ed25519.pub"

# Ensure GitHub host key is known
if ! ssh-keygen -F github.com &>/dev/null; then
  echo "Adding github.com to known_hosts..."
  ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
fi
chmod 644 "$HOME/.ssh/known_hosts"

# Ensure SSH config helps macOS remember/use the key
if [[ ! -f "$HOME/.ssh/config" ]] || ! grep -q "Host github.com" "$HOME/.ssh/config"; then
  echo "Configuring SSH for github.com..."
  cat >> "$HOME/.ssh/config" <<'EOF'

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
EOF
fi
chmod 600 "$HOME/.ssh/config"

# Install Nix if missing
if ! command -v nix &>/dev/null; then
  echo "Installing Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix | sh -s -- install

  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Ensure gh auth exists
if ! run_gh auth status &>/dev/null 2>&1; then
  echo "Authenticating with GitHub via gh..."
  run_gh auth login -h github.com -p ssh -w
fi

# Ensure gh token has scopes needed to manage SSH auth + signing keys
echo "Refreshing GitHub CLI auth scopes..."
run_gh auth refresh -h github.com -s admin:public_key -s admin:ssh_signing_key

# Start agent and load key
echo "Loading SSH key into ssh-agent..."
eval "$(ssh-agent -s)" >/dev/null

if ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" 2>/dev/null; then
  :
else
  ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null || true
fi

echo "Testing GitHub SSH authentication..."
if ! github_ssh_works; then
  echo ""
  echo "GitHub SSH is not ready yet."
  echo "Adding this machine's SSH public key to GitHub..."

  run_gh ssh-key add "$HOME/.ssh/id_ed25519.pub" \
    --type authentication \
    --title "$(hostname)"

  # Optional: also register same key for commit signing.
  # GitHub requires the key to be uploaded separately for auth and signing.
  run_gh ssh-key add "$HOME/.ssh/id_ed25519.pub" \
    --type signing \
    --title "$(hostname) signing" || true

  echo ""
  echo "Re-testing GitHub SSH authentication..."
  if ! github_ssh_works; then
    die "GitHub SSH authentication still failed. Fix SSH before continuing."
  fi
fi

echo ""
echo "GitHub SSH is working."

# Clone or update dotfiles using SSH
DOTFILES="$HOME/Developer/dotfiles"
mkdir -p "$HOME/Developer"

if [[ ! -d "$DOTFILES/.git" ]]; then
  echo "Cloning dotfiles via SSH..."
  git clone git@github.com:psteinroe/dotfiles.git "$DOTFILES"
else
  echo "Updating dotfiles..."
  git -C "$DOTFILES" remote set-url origin git@github.com:psteinroe/dotfiles.git
  git -C "$DOTFILES" pull
fi

# First run of nix-darwin
echo "Building system configuration..."
sudo HOME="$HOME" nix run nix-darwin -- switch --flake "$DOTFILES#psteinroe"

echo ""
echo "=== Done! ==="
echo "Your system is configured."
echo "Future updates: rebuild"
