#!/usr/bin/env bash
set -euo pipefail

# This script only runs nixos-anywhere against an already-created Hetzner
# server.  It does not create cloud servers, firewalls, or Rescue settings.
: "${HETZNER_IP:?Set HETZNER_IP to the server Rescue IP}"
: "${TAILSCALE_AUTHKEY:?Set TAILSCALE_AUTHKEY in the environment (it is never committed)}"

ROOT_DISK="${ROOT_DISK:-/dev/sda}"
ALLOW_NON_DEFAULT_ROOT_DISK="${ALLOW_NON_DEFAULT_ROOT_DISK:-}"
repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

configured_root_disk="$(
  nix eval --raw \
    "$repo_root#nixosConfigurations.hetzner-dev.config.disko.devices.disk.main.device"
)"
if [[ "$ROOT_DISK" != "$configured_root_disk" ]]; then
  printf '%s\n' \
    "Refusing ROOT_DISK=$ROOT_DISK: Disko is configured for $configured_root_disk." \
    "Update and review disko.nix, then pass the same ROOT_DISK value." >&2
  exit 1
fi
if [[ "$ROOT_DISK" != "/dev/sda" && "$ALLOW_NON_DEFAULT_ROOT_DISK" != "1" ]]; then
  printf '%s\n' \
    "Refusing non-default ROOT_DISK=$ROOT_DISK without explicit approval." \
    "Set ALLOW_NON_DEFAULT_ROOT_DISK=1 only after reviewing lsblk and disko.nix." >&2
  exit 1
fi

cat <<EOF
About to install declarative NixOS on $HETZNER_IP and erase its target disk.
The remote disk expected by this profile is $ROOT_DISK (/dev/sda by default).

Before continuing, ensure Rescue SSH is restricted to your IP and remove the
Rescue SSH rule/key before rebooting into the installed system.
EOF

printf 'Remote block devices (Rescue system):\n'
ssh -- "root@$HETZNER_IP" \
  'lsblk --output NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS'

printf '\nThis is destructive. Type HETZNER WIPE %s to continue: ' "$HETZNER_IP"
read -r confirmation
if [[ "$confirmation" != "HETZNER WIPE $HETZNER_IP" ]]; then
  echo "Confirmation did not match; aborting." >&2
  exit 1
fi

umask 077
extra_files="$(mktemp -d "${TMPDIR:-/tmp}/hetzner-nixos-extra.XXXXXX")"
cleanup() {
  rm -rf -- "$extra_files"
}
trap cleanup EXIT

# nixos-anywhere copies this tree to the target before the first boot.  Keep
# the auth key out of argv and make the temporary tree private as well.
mkdir -p -- "$extra_files/var/lib/tailscale-bootstrap"
printf '%s\n' "$TAILSCALE_AUTHKEY" \
  >"$extra_files/var/lib/tailscale-bootstrap/authkey"
chmod 600 "$extra_files/var/lib/tailscale-bootstrap/authkey"
unset TAILSCALE_AUTHKEY

cd "$repo_root"
nix run .#nixos-anywhere -- \
  --build-on-remote \
  --phases kexec,disko,install \
  --flake "$repo_root#hetzner-dev" \
  --extra-files "$extra_files" \
  --target-host "root@$HETZNER_IP"

cat <<EOF
NixOS was installed but has NOT been rebooted.

Before first boot:
  1. Remove the temporary public TCP 22 rule in the Hetzner Cloud firewall.
  2. Keep public UDP 41641 if direct Tailscale connectivity is desired.
  3. Reboot or power-cycle the server from the Hetzner console.
  4. Connect only through Tailscale as psteinroe.
EOF
