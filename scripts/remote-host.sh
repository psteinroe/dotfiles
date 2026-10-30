#!/usr/bin/env bash
# Transported over SSH by bin/remote. Never installs or replaces an operating system.
set -euo pipefail
umask 077
# Work on a classic NixOS install too; no global feature toggle is required first.
export NIX_CONFIG="${NIX_CONFIG:-}"$'\n''extra-experimental-features = nix-command flakes'
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$(id -un)/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
action=$1
ref=$2
force=$3
home_only=$4
nixos_flake=$5
allow_t3_update=$6
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
state="$HOME/.config/dotfiles"
checkout="$HOME/Developer/dotfiles"
fail() { printf 'remote: %s\n' "$*" >&2; exit 1; }

[[ $(uname -s) == Linux ]] || fail 'Only Linux development remotes are supported.'
[[ $(id -u) != 0 ]] || fail 'SSH as the existing development user, not root.'
if [[ $action != setup ]]; then
  [[ -f $state/remote.env ]] || fail 'Run remote setup HOST first.'
  # This file is written by setup and belongs to this SSH user.
  # shellcheck disable=SC1091
  source "$state/remote.env"
  ref=${ref:-$REMOTE_REF}
else
  ref=${ref:-main}
  if [[ $home_only == 1 ]]; then
    mode=home-manager
  else
    [[ -f /etc/NIXOS ]] || fail 'NixOS is the default. Use --home-manager on an existing non-NixOS system.'
    mode=nixos
  fi
fi

if [[ $action == status ]]; then
  printf 'Host: %s\nMode: %s\nBranch: %s\n' "$(hostname)" "$mode" "$REMOTE_REF"
  git -C "$checkout" status -sb
  printf '\nT3 version: '
  t3 --version
  systemctl --user --no-pager status t3code
  ip=$(tailscale ip -4 | head -n1)
  [[ $ip == 100.* ]] || fail 'No Tailscale IPv4 address.'
  curl --fail --connect-timeout 5 --max-time 10 -sS -o /dev/null -w 'T3 HTTP status: %{http_code}\n' "http://$ip:3773/"
  exit
fi

[[ $ref =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || fail 'Invalid branch name.'
if [[ -e $checkout ]]; then
  [[ -d $checkout/.git ]] || fail "$checkout exists but is not an ordinary Git clone."
  [[ $(git -C "$checkout" remote get-url origin) =~ ^(https://github.com/|git@github.com:)psteinroe/dotfiles(\.git)?$ ]] || fail 'Unexpected dotfiles origin; refusing to update it.'
  if [[ -n $(git -C "$checkout" status --porcelain --untracked-files=all) && $force != 1 ]]; then
    fail 'Dirty dotfiles checkout, including live Pi/T3 settings. Commit/stash first, or explicitly use --force to discard changes.'
  fi
  branch=$(git -C "$checkout" symbolic-ref --short HEAD || true)
  [[ $branch == "$ref" || $force == 1 ]] || fail "Checkout is on $branch, not $ref; use that --ref or explicitly --force."
fi

if [[ $action == setup ]]; then
  [[ -d /run/systemd/system ]] || fail 'T3 requires a systemd Linux host.'
  if [[ $mode == nixos ]]; then
    sudo -n true || fail 'NixOS setup/switch needs passwordless sudo.'
  fi
  if [[ $mode == nixos && -z $nixos_flake ]]; then
    [[ -f /etc/nixos/configuration.nix && ! -e /etc/nixos/flake.nix ]] || fail 'For an existing flake-based NixOS host, import nixosModules.remote there and pass --nixos-flake /etc/nixos#HOST. No OS config will be replaced.'
  fi
  if ! command -v nix >/dev/null; then
    [[ $mode == home-manager ]] || fail 'Nix is missing on this NixOS machine.'
    sudo -n true || fail 'Ask the administrator to install Nix, or provide passwordless sudo for initial setup.'
    command -v curl >/dev/null || fail 'Install curl first.'
    installer=$(mktemp)
    trap 'rm -f "$installer"' EXIT
    curl --proto '=https' --tlsv1.2 -fsSL https://install.determinate.systems/nix -o "$installer"
    sudo -n sh "$installer" install linux --no-confirm
    rm -f "$installer"
    trap - EXIT
  fi
  if [[ $mode == home-manager ]]; then
    if [[ -f /etc/NIXOS && ! -e /run/current-system/sw/share/nix-ld/lib/ld.so ]]; then
      fail "Ask the NixOS administrator to enable programs.nix-ld for the unmodified T3 binary."
    fi
    # Preserve existing settings; Determinate reads nix.custom.conf.
    conf=/etc/nix/nix.conf
    [[ ! -f /etc/nix/nix.custom.conf ]] || conf=/etc/nix/nix.custom.conf
    if ! nix config show substituters | grep -q 'cache.numtide.com'; then
      sudo -n true || fail 'Ask the administrator to trust the Numtide Nix cache before using Home Manager without sudo.'
      printf '\nextra-substituters = https://cache.numtide.com\nextra-trusted-substituters = https://cache.numtide.com\nextra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=\n' | sudo -n tee -a "$conf" >/dev/null
      sudo -n systemctl restart nix-daemon
    fi
    systemctl is-active --quiet tailscaled || fail 'Install, start and enroll Tailscale on the existing host first.'
  fi
  command -v git >/dev/null || fail 'Install Git on the remote first.'
  # Commit signing uses a host-local key; never copy a private key from the Mac.
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  if [[ ! -e $HOME/.ssh/id_ed25519 ]]; then
    ssh-keygen -q -t ed25519 -N "" -C "$(id -un)@$(hostname)" -f "$HOME/.ssh/id_ed25519"
  fi
  if [[ ! -d $checkout ]]; then
    mkdir -p "$(dirname "$checkout")"
    git clone --branch "$ref" https://github.com/psteinroe/dotfiles.git "$checkout"
  fi
fi

# No reset/clean without the explicit destructive flag. A diverged branch stops.
git -C "$checkout" fetch origin "$ref"
if [[ $force == 1 ]]; then
  git -C "$checkout" checkout -f -B "$ref" FETCH_HEAD
  git -C "$checkout" reset --hard FETCH_HEAD
  git -C "$checkout" clean -fd
else
  git -C "$checkout" merge --ff-only FETCH_HEAD
fi

case $(uname -m) in
  x86_64) system=x86_64-linux ;;
  aarch64|arm64) system=aarch64-linux ;;
  *) fail 'Only x86_64 and aarch64 Linux are supported.' ;;
esac
user=$(id -un)
# These strings enter a generated Nix expression; reject syntax rather than interpolate it.
[[ $user =~ ^[a-z_][a-z0-9_-]*$ && $HOME =~ ^/[a-zA-Z0-9_./-]+$ ]] || fail 'Unsupported user/home syntax.'
if [[ $action == setup ]]; then
  mkdir -p "$state"
  chmod 700 "$state"
  if [[ $mode == nixos && -n $nixos_flake ]]; then
    target=$nixos_flake
  else
    target="$state/flake"
    mkdir -p "$target"
    if [[ $mode == nixos ]]; then
      printf 'NixOS: this host switches to the dotfiles flake'\''s pinned nixpkgs-unstable, not its channel.\n'
      cat >"$target/flake.nix" <<EOF
{
  inputs.dotfiles.url = "git+file://$checkout";
  inputs.nixpkgs.follows = "dotfiles/nixpkgs";
  outputs = { dotfiles, nixpkgs, ... }: {
    nixosConfigurations.remote = nixpkgs.lib.nixosSystem {
      system = "$system";
      modules = [
        /etc/nixos/configuration.nix
        dotfiles.nixosModules.remote
        { dotfiles.remote.user = "$user"; dotfiles.remote.home = "$HOME"; }
      ];
    };
  };
}
EOF
      target="$target#remote"
    else
      cat >"$target/flake.nix" <<EOF
{
  inputs.dotfiles.url = "git+file://$checkout";
  outputs = { dotfiles, ... }: {
    homeConfigurations.remote = dotfiles.lib.mkHome {
      username = "$user";
      system = "$system";
      homeDirectory = "$HOME";
      isLinux = true;
    };
  };
}
EOF
      target="$target#remote"
    fi
  fi
  # Record the explicit target; no default host or global machine registry.
  umask 077
  printf 'mode=%q\ntarget=%q\nREMOTE_REF=%q\n' "$mode" "$target" "$ref" >"$state/remote.env"
fi

new_version=$(nix eval --raw "$checkout#lib.t3Version")
old_version=${DEPLOYED_T3_VERSION:-}
if [[ -z $old_version ]] && command -v t3 >/dev/null; then
  old_version=$(t3 --version | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
fi
if [[ -n $old_version && $old_version != "$new_version" ]]; then
  [[ $allow_t3_update == 1 ]] || fail "T3 changes $old_version → $new_version. Align desktop/mobile versions, then use --allow-t3-update to back up state and stop the service before switching."
  if [[ -d $HOME/.t3 ]]; then
    backup="$HOME/.local/state/dotfiles/backups/t3-$old_version-$(date +%Y%m%dT%H%M%S)"
    mkdir -p "$(dirname "$backup")"
    systemctl --user stop t3code
    cp -a "$HOME/.t3" "$backup"
    printf 'T3 state backup: %s\n' "$backup"
  fi
fi

# Refresh only the local checkout reference, never upstream pins. Existing NixOS
# flakes must declare their dotfiles input as the local checkout too.
flake_dir=${target%%#*}
# sudo resets the environment; keep the flake toggle for a classic host's first switch.
root=(sudo -n env "NIX_CONFIG=$NIX_CONFIG")
if [[ -w $flake_dir ]]; then
  nix flake lock --update-input dotfiles "$flake_dir"
else
  # A host-owned flake such as /etc/nixos is writable only by root.
  "${root[@]}" nix flake lock --update-input dotfiles "$flake_dir"
fi
if [[ $mode == nixos ]]; then
  managed_user=$(nix eval --impure --raw "$flake_dir#nixosConfigurations.${target##*#}.config.dotfiles.remote.user")
  [[ $managed_user == "$user" ]] || fail "The NixOS target must import nixosModules.remote for $user."
  "${root[@]}" nixos-rebuild switch --impure --flake "$target"
else
  if [[ $(loginctl show-user "$user" --property=Linger --value 2>/dev/null || true) != yes ]]; then
    sudo -n loginctl enable-linger "$user" || fail "Ask the administrator to run: loginctl enable-linger $user"
  fi
  nix run "$checkout#home-manager" -- switch --flake "$target"
fi
printf 'mode=%q\ntarget=%q\nREMOTE_REF=%q\nDEPLOYED_T3_VERSION=%q\n' "$mode" "$target" "$ref" "$new_version" >"$state/remote.env"
if ! tailscale status --json 2>/dev/null | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
  fail "Configuration applied. Enroll Tailscale with sudo tailscale up on this host, then run remote deploy HOST again."
fi
systemctl --user daemon-reload
systemctl --user restart t3code
systemctl --user is-active t3code
printf '\nUse remote status HOST to verify T3, remote auth HOST for logins, then remote connect HOST.\n'
