#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a headless Linux remote, especially exe.dev machines.
#
# Defaults assume exe.dev's model: SSH in as root, then create/use the normal
# development user: psteinroe. Override env vars only for repo/path/flake testing.

DEV_USER="${DEV_USER:-psteinroe}"
DOTFILES_REPO="${DOTFILES_REPO:-git@github.com:psteinroe/dotfiles.git}"
DOTFILES_HTTPS_REPO="${DOTFILES_HTTPS_REPO:-https://github.com/psteinroe/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-/home/${DEV_USER}/Developer/dotfiles}"
HM_FLAKE_ATTR="${HM_FLAKE_ATTR:-psteinroe@linux-x86_64}"
RUN_HOME_MANAGER="${RUN_HOME_MANAGER:-1}"
ALLOW_HOME_MANAGER_SKIP="${ALLOW_HOME_MANAGER_SKIP:-0}"
# Default to no in-VM GitHub auth. exe.dev provides GitHub access via
# integration proxy hosts, and public dotfiles can be cloned over HTTPS.
# Set GITHUB_AUTH=1 on generic remotes if you want gh auth + SSH key upload.
GITHUB_AUTH="${GITHUB_AUTH:-0}"
PASSWORDLESS_SUDO="${PASSWORDLESS_SUDO:-1}"

log() {
  printf '\n=== %s ===\n' "$*"
}

warn() {
  printf '\nWARN: %s\n' "$*" >&2
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

nix_profile=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

load_nix() {
  if [ -f "$nix_profile" ]; then
    # shellcheck disable=SC1090
    . "$nix_profile"
  fi
  export PATH="/nix/var/nix/profiles/default/bin:$PATH"
}

as_dev() {
  local script="$1"
  if [ "$(id -u)" -eq 0 ]; then
    sudo -H -u "$DEV_USER" \
      env DOTFILES_DIR="$DOTFILES_DIR" DOTFILES_REPO="$DOTFILES_REPO" \
        DOTFILES_HTTPS_REPO="$DOTFILES_HTTPS_REPO" HM_FLAKE_ATTR="$HM_FLAKE_ATTR" \
      bash -lc "source '$nix_profile' 2>/dev/null || true; export PATH=/nix/var/nix/profiles/default/bin:\$PATH; $script"
  else
    env DOTFILES_DIR="$DOTFILES_DIR" DOTFILES_REPO="$DOTFILES_REPO" \
      DOTFILES_HTTPS_REPO="$DOTFILES_HTTPS_REPO" HM_FLAKE_ATTR="$HM_FLAKE_ATTR" \
      bash -lc "source '$nix_profile' 2>/dev/null || true; export PATH=/nix/var/nix/profiles/default/bin:\$PATH; $script"
  fi
}

as_dev_tty() {
  local script="$1"
  if [ ! -r /dev/tty ]; then
    return 1
  fi

  if [ "$(id -u)" -eq 0 ]; then
    sudo -H -u "$DEV_USER" \
      env DOTFILES_DIR="$DOTFILES_DIR" DOTFILES_REPO="$DOTFILES_REPO" \
        DOTFILES_HTTPS_REPO="$DOTFILES_HTTPS_REPO" HM_FLAKE_ATTR="$HM_FLAKE_ATTR" \
      bash -lc "source '$nix_profile' 2>/dev/null || true; export PATH=/nix/var/nix/profiles/default/bin:\$PATH; $script" \
      </dev/tty
  else
    env DOTFILES_DIR="$DOTFILES_DIR" DOTFILES_REPO="$DOTFILES_REPO" \
      DOTFILES_HTTPS_REPO="$DOTFILES_HTTPS_REPO" HM_FLAKE_ATTR="$HM_FLAKE_ATTR" \
      bash -lc "source '$nix_profile' 2>/dev/null || true; export PATH=/nix/var/nix/profiles/default/bin:\$PATH; $script" \
      </dev/tty
  fi
}

if [ "$(uname -s)" != "Linux" ]; then
  echo "bootstrap-remote.sh is for Linux remotes only. Use bootstrap.sh on macOS." >&2
  exit 1
fi

log "Preparing base OS packages"
if command -v apt-get >/dev/null 2>&1; then
  as_root apt-get update
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    bash ca-certificates curl git openssh-client sudo tar xz-utils
else
  warn "apt-get not found; assuming curl/git/ssh/sudo are already available"
fi

log "Ensuring development user: ${DEV_USER}"
if ! id "$DEV_USER" >/dev/null 2>&1; then
  as_root useradd -m -s /bin/bash "$DEV_USER"
fi

if command -v usermod >/dev/null 2>&1 && getent group sudo >/dev/null 2>&1; then
  as_root usermod -aG sudo "$DEV_USER"
fi

if [ "$PASSWORDLESS_SUDO" = "1" ] && [ "$(id -u)" -eq 0 ]; then
  echo "${DEV_USER} ALL=(ALL) NOPASSWD:ALL" >/tmp/dotfiles-bootstrap-sudoers
  as_root install -m 0440 /tmp/dotfiles-bootstrap-sudoers "/etc/sudoers.d/${DEV_USER}-dotfiles-bootstrap"
  rm -f /tmp/dotfiles-bootstrap-sudoers
fi

log "Installing Determinate Nix"
if ! command -v nix >/dev/null 2>&1 && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  install_args=(install linux --no-confirm)

  if [ ! -d /run/systemd/system ]; then
    warn "systemd was not detected; installing Nix with --init none. Nix will be root-only in this mode."
    install_args+=(--init none)
  fi

  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
    sh -s -- "${install_args[@]}"
else
  echo "Nix already installed."
fi
load_nix
nix --version

log "Preparing SSH key"
as_dev 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && if [ ! -f ~/.ssh/id_ed25519 ]; then ssh-keygen -t ed25519 -C "psteinroe@$(hostname)" -N "" -f ~/.ssh/id_ed25519; fi && chmod 600 ~/.ssh/id_ed25519 && chmod 644 ~/.ssh/id_ed25519.pub'

should_auth=0
case "$GITHUB_AUTH" in
  1|true|yes) should_auth=1 ;;
  0|false|no) should_auth=0 ;;
  auto)
    if [ -r /dev/tty ]; then should_auth=1; else should_auth=0; fi
    ;;
  *) warn "Unknown GITHUB_AUTH=${GITHUB_AUTH}; skipping GitHub auth" ;;
esac

if [ "$should_auth" = "1" ]; then
  log "Authenticating GitHub CLI"
  if ! as_dev 'nix run nixpkgs#gh -- auth status >/dev/null 2>&1'; then
    as_dev_tty 'nix run nixpkgs#gh -- auth login -p ssh -w'
  fi

  log "Registering SSH key with GitHub"
  as_dev 'nix run nixpkgs#gh -- ssh-key add ~/.ssh/id_ed25519.pub --type authentication --title "$(hostname)-auth" 2>/dev/null || true'
  as_dev 'nix run nixpkgs#gh -- ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "$(hostname)-signing" 2>/dev/null || true'
else
  warn "Skipping interactive GitHub auth. Public key for manual registration:"
  as_dev 'cat ~/.ssh/id_ed25519.pub'
fi

log "Cloning or updating dotfiles"
as_dev 'mkdir -p "$(dirname "$DOTFILES_DIR")"'
if as_dev '[ -d "$DOTFILES_DIR/.git" ]'; then
  as_dev 'git -C "$DOTFILES_DIR" fetch --prune origin && upstream=$(git -C "$DOTFILES_DIR" rev-parse --abbrev-ref --symbolic-full-name "@{upstream}" 2>/dev/null || printf "origin/main") && git -C "$DOTFILES_DIR" reset --hard "$upstream" && git -C "$DOTFILES_DIR" clean -fd'
else
  if as_dev 'nix run nixpkgs#gh -- auth status >/dev/null 2>&1'; then
    as_dev 'git clone "$DOTFILES_REPO" "$DOTFILES_DIR"'
  else
    as_dev 'git clone "$DOTFILES_HTTPS_REPO" "$DOTFILES_DIR"'
  fi
fi

if [ "$RUN_HOME_MANAGER" = "1" ]; then
  log "Applying Home Manager: ${HM_FLAKE_ATTR}"
  if as_dev 'cd "$DOTFILES_DIR" && nix run nixpkgs#home-manager -- switch --flake "$DOTFILES_DIR#$HM_FLAKE_ATTR"'; then
    echo "Home Manager switch completed."
  elif [ "$ALLOW_HOME_MANAGER_SKIP" = "1" ]; then
    warn "Home Manager switch failed. Continuing only because ALLOW_HOME_MANAGER_SKIP=1."
    warn "Re-run with:"
    warn "  sudo -iu ${DEV_USER} bash -lc 'cd ${DOTFILES_DIR} && nix run nixpkgs#home-manager -- switch --flake .#${HM_FLAKE_ATTR}'"
  else
    warn "Home Manager switch failed. Re-run with ALLOW_HOME_MANAGER_SKIP=1 only if you intentionally want a partial bootstrap."
    exit 1
  fi
fi

log "Done"
echo "Remote bootstrap finished."
echo "User:        ${DEV_USER}"
echo "Dotfiles:    ${DOTFILES_DIR}"
echo "HM flake:    ${HM_FLAKE_ATTR}"
echo "Next shell:  sudo -iu ${DEV_USER}"
