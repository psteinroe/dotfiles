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
# The standalone Linux profile uses direct tailnet binding for T3 and does not
# need Tailscale operator privileges. Set this only when opting into Serve.
CONFIGURE_TAILSCALE_OPERATOR="${CONFIGURE_TAILSCALE_OPERATOR:-0}"
# Protect standalone Linux remotes from becoming unresponsive under memory
# pressure. The earlyoom binary comes from Home Manager; root-owned host state
# is provisioned below because standalone Home Manager cannot manage it.
CONFIGURE_MEMORY_GUARD="${CONFIGURE_MEMORY_GUARD:-1}"
MEMORY_GUARD_ONLY="${MEMORY_GUARD_ONLY:-0}"
MEMORY_GUARD_SWAP_GIB="${MEMORY_GUARD_SWAP_GIB:-8}"

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

configure_memory_guard() {
  if [ ! -d /run/systemd/system ] || ! command -v systemctl >/dev/null 2>&1; then
    warn "systemd was not detected; skipping the memory-pressure guard."
    return
  fi

  case "$MEMORY_GUARD_SWAP_GIB" in
    ''|0*|*[!0-9]*)
      warn "MEMORY_GUARD_SWAP_GIB must be a positive integer, got: ${MEMORY_GUARD_SWAP_GIB}"
      exit 1
      ;;
  esac

  local earlyoom_bin
  earlyoom_bin="$(as_dev 'earlyoom_path=$(command -v earlyoom 2>/dev/null || true); if [ -n "$earlyoom_path" ]; then readlink -f "$earlyoom_path"; fi')"
  case "$earlyoom_bin" in
    /nix/store/*-earlyoom-*/bin/earlyoom) ;;
    *)
      warn "A Nix-managed earlyoom binary was not found after Home Manager activation."
      warn "Expected /nix/store/*-earlyoom-*/bin/earlyoom, got: ${earlyoom_bin:-<empty>}"
      exit 1
      ;;
  esac
  if [ ! -x "$earlyoom_bin" ]; then
    warn "Nix-managed earlyoom binary is not executable: ${earlyoom_bin}"
    exit 1
  fi

  for command_name in blkid fallocate mkswap swapon sysctl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      warn "Required host command is unavailable: ${command_name}"
      exit 1
    fi
  done

  log "Configuring ${MEMORY_GUARD_SWAP_GIB} GiB swapfile"
  local swapfile=/swapfile
  local fstab_entry='/swapfile none swap sw,nofail 0 0'
  local fstab_swap_count
  fstab_swap_count="$(awk '$0 !~ /^[[:space:]]*#/ && $1 == "/swapfile" { count++ } END { print count + 0 }' /etc/fstab)"
  if [ "$fstab_swap_count" -gt 1 ]; then
    warn "Multiple /swapfile entries already exist in /etc/fstab."
    exit 1
  elif [ "$fstab_swap_count" -eq 1 ] && ! grep -Fxq "$fstab_entry" /etc/fstab; then
    warn "A conflicting /swapfile entry already exists in /etc/fstab."
    exit 1
  fi

  if [ -L "$swapfile" ]; then
    warn "Refusing to replace swapfile symlink: ${swapfile}"
    exit 1
  fi

  local expected_swap_bytes=$((MEMORY_GUARD_SWAP_GIB * 1024 * 1024 * 1024))
  local created_swapfile=0
  if [ -e "$swapfile" ]; then
    if [ ! -f "$swapfile" ]; then
      warn "Refusing to replace non-regular swap path: ${swapfile}"
      exit 1
    fi

    local actual_swap_bytes
    actual_swap_bytes="$(stat -c %s "$swapfile")"
    if [ "$actual_swap_bytes" -ne "$expected_swap_bytes" ]; then
      warn "Existing ${swapfile} is ${actual_swap_bytes} bytes; expected ${expected_swap_bytes}."
      warn "Refusing to resize an existing swapfile automatically."
      exit 1
    fi

    if ! as_root blkid -p -s TYPE -o value "$swapfile" 2>/dev/null | grep -qx swap; then
      warn "Existing ${swapfile} does not contain a swap signature; refusing to overwrite it."
      exit 1
    fi
  else
    local available_kib required_kib
    available_kib="$(df -Pk / | awk 'NR == 2 { print $4 }')"
    required_kib=$(((MEMORY_GUARD_SWAP_GIB + 4) * 1024 * 1024))
    if [ "$available_kib" -lt "$required_kib" ]; then
      warn "Not enough free disk for swap plus a 4 GiB reserve."
      exit 1
    fi

    if ! as_root fallocate -l "${MEMORY_GUARD_SWAP_GIB}G" "$swapfile"; then
      as_root rm -f "$swapfile"
      warn "Could not allocate ${swapfile}."
      exit 1
    fi
    as_root chmod 0600 "$swapfile"
    if ! as_root mkswap "$swapfile"; then
      as_root rm -f "$swapfile"
      warn "Could not initialize ${swapfile}; removed the incomplete file."
      exit 1
    fi
    created_swapfile=1
  fi
  as_root chmod 0600 "$swapfile"

  if ! swapon --show=NAME --noheadings --raw | grep -Fxq "$swapfile"; then
    if ! as_root swapon "$swapfile"; then
      if [ "$created_swapfile" -eq 1 ]; then
        as_root rm -f "$swapfile"
      fi
      warn "Could not activate ${swapfile}; it was not added to /etc/fstab."
      exit 1
    fi
  fi

  if [ "$fstab_swap_count" -eq 0 ]; then
    printf '%s\n' "$fstab_entry" | as_root tee -a /etc/fstab >/dev/null
  fi

  log "Configuring memory-pressure policy"
  local sysctl_config earlyoom_unit
  sysctl_config="$(mktemp)"
  earlyoom_unit="$(mktemp)"
  cat >"$sysctl_config" <<'EOF'
# Managed by psteinroe/dotfiles bootstrap-remote.sh.
vm.swappiness=10
EOF
  as_root install -m 0644 "$sysctl_config" /etc/sysctl.d/99-rdev-memory-pressure.conf
  rm -f "$sysctl_config"
  as_root sysctl -p /etc/sysctl.d/99-rdev-memory-pressure.conf

  local earlyoom_store earlyoom_gcroot
  earlyoom_store="${earlyoom_bin%/bin/earlyoom}"
  earlyoom_gcroot=/nix/var/nix/gcroots/rdev-earlyoom
  if as_root test -e "$earlyoom_gcroot" && ! as_root test -L "$earlyoom_gcroot"; then
    warn "Refusing to replace non-symlink Nix GC root: ${earlyoom_gcroot}"
    exit 1
  fi
  as_root mkdir -p /nix/var/nix/gcroots
  as_root ln -sfn "$earlyoom_store" "$earlyoom_gcroot"

  cat >"$earlyoom_unit" <<EOF
# Managed by psteinroe/dotfiles bootstrap-remote.sh.
[Unit]
Description=Early OOM daemon for remote development workloads
Documentation=https://github.com/rfjakob/earlyoom
After=local-fs.target swap.target

[Service]
Type=simple
ExecStart=${earlyoom_bin} -m 10,5 -s 100,100 -r 60 --prefer '^(tsc|tsgo|vitest|esbuild)\$' --avoid '^(herdr|pi|sshd|sshd-session|sshd-auth|tailscaled|dockerd|containerd|postgres|node-MainThread)\$'
Restart=on-failure
RestartSec=5s
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF
  as_root install -m 0644 "$earlyoom_unit" /etc/systemd/system/earlyoom.service
  rm -f "$earlyoom_unit"
  as_root systemctl daemon-reload
  as_root systemctl enable earlyoom.service
  as_root systemctl restart earlyoom.service
}

if [ "$(uname -s)" != "Linux" ]; then
  echo "bootstrap-remote.sh is for Linux remotes only. Use bootstrap.sh on macOS." >&2
  exit 1
fi

if [ "$MEMORY_GUARD_ONLY" = "1" ]; then
  configure_memory_guard
  log "Memory-pressure guard updated"
  exit 0
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

# Keep the managed user's systemd services running without an active SSH
# login. This is required by long-lived remote services such as moshi-hook and
# T3 Code. On non-systemd hosts this is optional, so do not abort bootstrap.
if [ -d /run/systemd/system ] && command -v loginctl >/dev/null 2>&1; then
  if ! as_root loginctl enable-linger "$DEV_USER"; then
    warn "Could not enable systemd lingering for ${DEV_USER}; continuing bootstrap."
  fi
else
  warn "systemd was not detected; skipping user lingering for ${DEV_USER}."
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

log "Configuring Nix binary caches"
cache_config=$(mktemp)
cat >"$cache_config" <<'EOF'
# Managed by psteinroe/dotfiles.
extra-substituters = https://cache.numtide.com
extra-trusted-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
EOF
as_root install -m 0644 "$cache_config" /etc/nix/nix.custom.conf
rm -f "$cache_config"

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

if [ "$CONFIGURE_MEMORY_GUARD" = "1" ]; then
  configure_memory_guard
else
  echo "Memory-pressure guard setup disabled (CONFIGURE_MEMORY_GUARD=${CONFIGURE_MEMORY_GUARD})."
fi

if [ "$CONFIGURE_TAILSCALE_OPERATOR" = "1" ]; then
  log "Configuring Tailscale operator"
  tailscale_bin="$(as_dev 'command -v tailscale' 2>/dev/null || true)"
  if [ -z "$tailscale_bin" ]; then
    warn "Tailscale CLI is not available after Home Manager activation."
    warn "Cannot enable the explicitly requested Tailscale Serve transport."
    exit 1
  else
    tailscale_state="$(as_root "$tailscale_bin" status --json 2>/dev/null || true)"
    if ! printf '%s\n' "$tailscale_state" | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
      warn "Tailscale daemon is not running or this host is not enrolled."
      warn "Enroll the host, then rerun with CONFIGURE_TAILSCALE_OPERATOR=1."
      exit 1
    else
      operator_prefs="$(as_root "$tailscale_bin" debug prefs 2>/dev/null || true)"
      current_operator="$({
        printf '%s\n' "$operator_prefs" \
          | sed -n 's/.*"OperatorUser"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
      } || true)"

      if [ -n "$current_operator" ] && [ "$current_operator" != "$DEV_USER" ]; then
        warn "Tailscale operator is already ${current_operator}; refusing to replace it with ${DEV_USER}."
        exit 1
      elif [ "$current_operator" != "$DEV_USER" ] \
        && ! as_root "$tailscale_bin" set --operator="$DEV_USER"; then
        warn "Could not configure Tailscale operator=${DEV_USER}."
        warn "Run: sudo tailscale set --operator=${DEV_USER}"
        exit 1
      fi
    fi
  fi
else
  echo "Tailscale operator setup is not needed for the direct-tailnet T3 transport."
fi

log "Done"
echo "Remote bootstrap finished."
echo "User:        ${DEV_USER}"
echo "Dotfiles:    ${DOTFILES_DIR}"
echo "HM flake:    ${HM_FLAKE_ATTR}"
echo "Next shell:  sudo -iu ${DEV_USER}"
