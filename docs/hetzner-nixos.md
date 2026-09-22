# Hetzner NixOS remote-dev host

This repository contains a prepared `nixosConfigurations.hetzner-dev` target for replacing the current exe.dev machine. Nothing in this configuration creates a Hetzner server or changes a Hetzner Cloud firewall automatically.

## Architecture

```text
Mac / phone
  -> private Tailscale network
  -> psteinroe-dev-hetzner (NixOS)
  -> OpenSSH, Mosh, T3 Code, and Home Manager user services
```

NixOS owns the host, account, firewall, OpenSSH, Docker, Tailscale, disks, and boot loader. Home Manager reuses the normal Linux shell, editor, agent, Moshi, and T3 modules.

Security defaults:

- no public TCP application ports after installation;
- SSH is accepted only on `tailscale0`;
- Mosh UDP 60000–61000 is accepted only on `tailscale0`;
- Tailscale's WireGuard UDP transport is allowed publicly;
- password and root SSH logins are disabled;
- Tailscale and T3 credentials remain mutable state and are not in the Nix store or Git;
- Hetzner Rescue remains the out-of-band recovery path.

## Assumptions

The checked-in Disko profile is intentionally explicit and destructive. It assumes a normal x86_64 Hetzner Cloud VM with its only root disk at `/dev/sda`. It creates a dual BIOS/UEFI GPT layout:

- 1 MiB BIOS boot partition;
- 512 MiB FAT EFI system partition mounted at `/boot`;
- the remaining space as ext4 mounted at `/`.

Do not run the installer if `lsblk` shows a different target. Change `nix/nixos/hosts/hetzner-dev/disko.nix`, review it, and rebuild instead of guessing during installation.

The profile uses NixOS's Nix daemon. Do not install Determinate Nix inside NixOS; equivalent flake, trusted-user, and binary-cache settings are declarative in `nix/nixos/modules/base.nix`.

## Before installation

1. Create an x86_64 Hetzner Cloud server with at least 2 GiB RAM.
2. Create a temporary Hetzner Cloud firewall rule allowing public TCP 22 only from your current public IP. Allow UDP 41641 for direct Tailscale transport. Do not open public T3, Mosh, or Docker ports.
3. Enable the Hetzner Linux Rescue system and reboot into it.
4. Create a Tailscale auth key in the existing `psteinroe.github` tailnet:
   - preauthorized;
   - one-off/non-reusable;
   - **not ephemeral**, because this is a persistent machine;
   - short expiry.

Keep the key in a password manager or local environment only. Do not put it in a command argument, shell history, Nix file, or Git.

## Validate the profile

From the dotfiles checkout:

```bash
nix flake check --no-build
nix eval .#nixosConfigurations.hetzner-dev.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.hetzner-dev.config.system.build.diskoScript.drvPath
```

An x86_64 Linux builder can additionally build both outputs:

```bash
nix build .#nixosConfigurations.hetzner-dev.config.system.build.toplevel
nix build .#nixosConfigurations.hetzner-dev.config.system.build.diskoScript
```

The installer uses `--build-on-remote`, so an Apple Silicon Mac does not need to build the Linux closure locally.

## Install from Rescue

Export the secret without putting its value in history, then run the guarded installer:

```bash
read -r -s 'TAILSCALE_AUTHKEY?Tailscale auth key: '
export TAILSCALE_AUTHKEY
export HETZNER_IP=<public-rescue-ip>
./bootstrap-hetzner-nixos.sh
unset TAILSCALE_AUTHKEY
```

The script:

1. shows remote `lsblk` output;
2. requires a typed destructive confirmation;
3. puts the auth key in a mode-0700 temporary `--extra-files` tree;
4. invokes the lock-file-pinned `nixos-anywhere` app;
5. builds on the x86_64 Rescue host;
6. installs without rebooting.

After the script finishes, remove the temporary public TCP 22 rule from the Hetzner Cloud firewall, then reboot or power-cycle from the Hetzner console. This ordering prevents a public-SSH window on first boot. Keep UDP 41641 if direct Tailscale connectivity is desired.

On first boot, `tailscale-bootstrap.service` reads `/var/lib/tailscale-bootstrap/authkey`, enrolls as `psteinroe-dev-hetzner`, assigns `psteinroe` as the local Tailscale operator, and deletes the key only after success. Durable Tailscale state remains under `/var/lib/tailscale`.

## First login and validation

Wait for the new node to appear, then use the prepared alias:

```bash
tailscale ping psteinroe-dev-hetzner
ssh rdev-hetzner 'hostname; id; systemctl is-active tailscaled sshd docker'
ssh rdev-hetzner 'systemctl --user is-active t3code moshi-hook'
ssh rdev-hetzner 'sudo nft list ruleset'
```

Clone the writable deployment checkout. Home Manager itself boots from the immutable flake source, so this clone is for updates and remote helper workflows:

```bash
ssh rdev-hetzner 'mkdir -p ~/Developer && git clone https://github.com/psteinroe/dotfiles.git ~/Developer/dotfiles'
```

Copy mutable credentials explicitly with the existing `rauth` workflow only after reviewing what is needed. Do not copy `~/.t3` unless intentionally migrating all T3 server state; fresh pairing is safer.

Validate the normal workflow before cutover:

```bash
RDEV_HOST=rdev-hetzner rrebuild
RDEV_HOST=rdev-hetzner rdev dotfiles main
ssh rdev-hetzner 'command -v herdr && command -v t3 && command -v tmux'
ssh -T rdev-hetzner 'for i in $(seq 1 60); do date; sleep 1; done'
```

For T3 Code, first verify normal TLS 1.3 rather than only TLS 1.2:

```bash
ssh rdev-hetzner 'tailscale serve status'
curl --max-time 15 https://psteinroe-dev-hetzner.tail6aabd2.ts.net/.well-known/t3/environment
ssh -t rdev-hetzner 't3 pair --tailscale'
```

The NixOS profile initially uses Tailscale Serve HTTPS. Moving from exe.dev does not mathematically guarantee that a Tailscale Serve/netstack regression disappears, so the default TLS 1.3 probe is a required acceptance check. If the same large post-quantum ClientHello stalls, change `hetznerT3codeTransport` in `flake.nix` to `"tailscale-direct"` and pair with `t3 pair`. That single setting also opens TCP 3773 only on `tailscale0`; it never opens the port publicly. Do not silently disable post-quantum TLS globally.

Also test Mosh from the phone on the private hostname before declaring the migration complete.

## Cutover

`rdev` intentionally continues to target exe.dev until the new host is tested. `rdev-hetzner` already targets the future MagicDNS name, not a public or ephemeral Hetzner IP.

After the checks pass:

1. change the `Host rdev` `HostName` in `ssh_config` to `psteinroe-dev-hetzner.tail6aabd2.ts.net`;
2. keep `rdev-exe` as the old provider recovery path during burn-in;
3. update Moshi/T3 pairings for the new server;
4. keep the old machine until active worktrees and mutable application state are accounted for;
5. then delete the old machine through its provider.

No DNS or dotfiles change is needed if Hetzner later replaces the VM while retaining the same Tailscale machine name.

## Updates and recovery

On the NixOS host, `rebuild` detects `/etc/NIXOS` and runs:

```bash
sudo nixos-rebuild switch --flake ~/Developer/dotfiles#hetzner-dev
```

NixOS generations provide normal configuration rollback. Disk loss or an unbootable host uses Hetzner Rescue: temporarily permit Rescue SSH from the administrator's IP, inspect or reinstall, then remove the public rule again. `rdev-exe` remains independent of the new host during migration.
