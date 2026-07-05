# Hetzner Remote Dev Plan — NixOS

## Goal

Run the remote-dev machine on Hetzner as a fully declarative NixOS host while preserving the same local workflow:

```bash
rdev hellomateo dev
rwtlist hellomateo
rssh
rpi hellomateo dev
```

This is the cleaner long-term version of the Hetzner setup. It should make the host reproducible from the dotfiles flake instead of relying on an imperative Ubuntu/Debian bootstrap.

## Target architecture

```text
Mac rdev -> ssh rdev -> Hetzner NixOS over Tailscale -> psteinroe -> tmux/Home Manager dev env
```

NixOS owns system-level state:

- users
- SSH daemon
- Tailscale daemon
- sudo policy
- firewall
- system packages/services

Home Manager owns user-level state:

- shell config
- editor config
- tmux config
- dev tools
- remote helper functions
- Pi/agent config

## Why this is a separate plan

The current remote setup is standalone Home Manager on an Ubuntu-ish machine. Moving to NixOS is not just a provider swap because system services become declarative and paths may differ.

Important current assumptions to revisit:

- `rdev-host` hardcodes `/home/psteinroe/.nix-profile/bin/zsh`.
- `nix/home/linux.nix` sets tmux default shell to `/home/psteinroe/.nix-profile/bin/zsh`.
- The exe.dev path SSHes as `exedev` and then runs `sudo -u psteinroe`.
- A NixOS Home Manager module may expose packages under `/etc/profiles/per-user/psteinroe/bin` rather than only `~/.nix-profile/bin`.

The NixOS plan should remove or parameterize those assumptions.

## Deployment options

### Option A: Hetzner rescue boot + nixos-anywhere

Recommended if comfortable with NixOS remote installs.

High-level flow:

1. Create Hetzner server.
2. Boot into rescue system.
3. Run `nixos-anywhere` from the Mac using a NixOS configuration from this flake.
4. Reboot into NixOS.
5. Connect over Tailscale/OpenSSH.

Example shape:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#hetzner-dev \
  root@<hetzner-public-ip>
```

### Option B: Hetzner NixOS image + flake switch

If using a community/official NixOS image:

1. Provision NixOS image.
2. SSH as root.
3. Clone dotfiles.
4. Run `nixos-rebuild switch --flake .#hetzner-dev`.

This may be simpler operationally but depends on available Hetzner image choices.

## Proposed flake shape

Add a NixOS host output next to the existing Home Manager output:

```nix
nixosConfigurations.hetzner-dev = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = {
    inherit inputs username;
    homeDirectory = "/home/${username}";
    dotfilesPath = "/home/${username}/Developer/dotfiles";
    isDarwin = false;
    isLinux = true;
  };
  modules = [
    ./nix/nixos/hetzner-dev.nix
    home-manager.nixosModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.${username} = import ./nix/home;
      home-manager.extraSpecialArgs = {
        inherit inputs username;
        homeDirectory = "/home/${username}";
        dotfilesPath = "/home/${username}/Developer/dotfiles";
        isDarwin = false;
        isLinux = true;
      };
    }
  ];
};
```

Keep the existing standalone Home Manager output:

```nix
homeConfigurations."psteinroe@linux-x86_64"
```

That output remains useful for Ubuntu/Debian bootstrap remotes and non-NixOS machines.

## Proposed NixOS module

Create something like `nix/nixos/hetzner-dev.nix`:

```nix
{ config, pkgs, lib, username, ... }:

{
  imports = [
    ./hardware/hetzner-dev.nix
  ];

  networking.hostName = "psteinroe-dev-hetzner";

  users.users.${username} = {
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 <local-public-key>"
    ];
  };

  programs.zsh.enable = true;

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  services.tailscale.enable = true;

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedTCPPorts = [ 22 ]; # temporary during bootstrap; later restrict in Hetzner firewall
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    vim
    tmux
    tailscale
  ];

  system.stateVersion = "26.05";
}
```

The hardware/import layout will depend on the installer approach.

## Tailscale auth on NixOS

Declaratively enabling the daemon is easy:

```nix
services.tailscale.enable = true;
```

Authentication is still a secret-bearing action. Options:

### Manual first login

After install:

```bash
sudo tailscale up --ssh=false --hostname psteinroe-dev-hetzner
```

Simplest and safest for the first version.

### Auth key via deployment secret

Use an ephemeral Tailscale auth key during install/deploy:

```bash
sudo tailscale up --ssh=false --hostname psteinroe-dev-hetzner --auth-key "$TAILSCALE_AUTHKEY"
```

Do not commit the auth key to the repo. If this becomes permanent, use a secret manager such as `sops-nix`/agenix or an out-of-band deploy environment variable.

## SSH config target

After NixOS is reachable over Tailscale:

```sshconfig
Host rdev
  HostName psteinroe-dev-hetzner
  User psteinroe
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m

Host rdev-exe
  HostName psteinroe-dev.exe.xyz
  User exedev
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
```

## Required dotfiles changes before relying on NixOS

### 1. Remove hardcoded Home Manager profile paths

Current code assumes:

```text
/home/psteinroe/.nix-profile/bin/zsh
```

On NixOS, prefer one of these:

- use `/run/current-system/sw/bin/zsh` for system zsh
- use `command -v zsh` after setting a robust remote `PATH`
- include both `/etc/profiles/per-user/psteinroe/bin` and `~/.nix-profile/bin` in remote PATH

Recommended remote PATH:

```text
/home/psteinroe/.local/bin:/etc/profiles/per-user/psteinroe/bin:/home/psteinroe/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin
```

Update:

- `zsh/functions/rdev-host`
- `nix/home/linux.nix` tmux `default-shell`/`default-command`
- any other wrapper that calls `~/.nix-profile/bin/zsh` directly

### 2. Make `sudo -u psteinroe` optional

For NixOS, SSH should normally connect directly as `psteinroe`.

Current exe.dev flow needs:

```bash
exedev -> sudo -u psteinroe
```

NixOS/Hetzner flow should be:

```bash
psteinroe -> zsh/tmux directly
```

Add a wrapper option or detection layer so both transports work:

- `RDEV_REMOTE_USER=psteinroe`
- `RDEV_SUDO_USER=psteinroe` only for exe.dev-style hosts
- no sudo when SSH user already equals remote user

### 3. Add NixOS-specific modules under `nix/nixos/`

Suggested tree:

```text
nix/nixos/
  hetzner-dev.nix
  hardware/
    hetzner-dev.nix
```

Keep Darwin/Home Manager modules separate.

### 4. Document deployment

Add README section or link to this plan with:

- install command
- first Tailscale auth command
- SSH validation
- wrapper validation
- rollback/recovery path

## Validation sequence

After deployment:

```bash
ssh psteinroe@<public-ip> 'hostname && id'
ssh psteinroe@<public-ip> 'command -v zsh && command -v tmux'
ssh psteinroe@<public-ip> 'sudo tailscale status || true'
```

Authenticate Tailscale if needed:

```bash
ssh psteinroe@<public-ip> 'sudo tailscale up --ssh=false --hostname psteinroe-dev-hetzner'
```

Then validate from the Mac:

```bash
tailscale status
tailscale ping psteinroe-dev-hetzner
ssh rdev 'echo ok'
ssh -T rdev 'for i in $(seq 1 60); do date; sleep 1; done'
rwtlist hellomateo
rdev hellomateo dev
rpi hellomateo dev
```

## Migration sequence

1. Add NixOS config to flake without changing the current `rdev` default.
2. Build/check locally:

   ```bash
   nix flake check
   nix build .#nixosConfigurations.hetzner-dev.config.system.build.toplevel
   ```

3. Install NixOS on a new Hetzner server.
4. Authenticate Tailscale.
5. Add temporary SSH host `rdev-nixos`.
6. Test wrappers with:

   ```bash
   RDEV_HOST=rdev-nixos rdev hellomateo dev
   ```

7. Fix path/sudo assumptions until wrappers work.
8. Flip `rdev` to the NixOS host.
9. Keep `rdev-exe` or `rdev-hetzner-bootstrap` available as fallback during burn-in.

## Rollback plan

Because this should be a new server, rollback is mostly DNS/SSH alias based:

```bash
RDEV_HOST=rdev-exe rdev hellomateo dev
RDEV_HOST=rdev-hetzner rdev hellomateo dev
```

If the NixOS deploy fails, rebuild from rescue mode or discard the Hetzner server and recreate it from the flake once fixed.

## Acceptance criteria

- `nix build .#nixosConfigurations.hetzner-dev.config.system.build.toplevel` succeeds.
- Hetzner server boots into NixOS.
- `psteinroe` can SSH in with the local key.
- `tailscaled` is enabled and the host appears in the tailnet.
- `rdev`/`rwtlist`/`rpi` work against the NixOS host over Tailscale.
- No wrapper requires the exe.dev `exedev -> sudo -u psteinroe` path for the NixOS host.
- `rdev-exe` or another fallback remains available during migration.

## Open questions

- Use `nixos-anywhere`, a Hetzner NixOS image, or a custom image?
- Commit hardware config for one named server, or generate it during install?
- Use standalone Home Manager on NixOS to preserve `~/.nix-profile`, or use the NixOS Home Manager module and fix paths properly?
- Where should Tailscale auth keys live if unattended deployment is desired?
- Should the public SSH port remain open after Tailscale is working?
- Should Hetzner backups/snapshots be enabled declaratively or managed in the Hetzner UI/API?
