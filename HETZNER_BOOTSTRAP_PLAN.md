# Hetzner Remote Dev Plan — Bootstrap Script

## Goal

Run the existing remote-dev workflow on a normal Hetzner Linux server while keeping the user-facing commands unchanged:

```bash
rdev hellomateo dev
rwtlist hellomateo
rssh
rpi hellomateo dev
```

This plan intentionally reuses the current `bootstrap-remote.sh` + standalone Home Manager model. It is the fastest path to move off exe.dev as the daily remote while keeping exe.dev available as a fallback if desired.

## Target architecture

```text
Mac rdev -> ssh rdev -> Hetzner server over Tailscale -> psteinroe -> tmux/Home Manager dev env
```

Compared with the current exe.dev setup:

- no exe.dev SSH gateway
- no `exedev -> sudo -u psteinroe` hop required long term
- same Nix/Home Manager user environment
- same remote worktree/tmux/Pi wrapper semantics

## Assumptions

- Server OS: Ubuntu or Debian on Hetzner Cloud.
- Server has systemd, apt, OpenSSH, and root SSH during initial provisioning.
- Tailscale will be the normal network path.
- Plain OpenSSH over Tailscale is preferred initially; Tailscale SSH can be considered later.
- The remote development user remains `psteinroe`.

## Provisioning sequence

### 1. Create the Hetzner server

Create a small x86_64 Hetzner Cloud server with an Ubuntu/Debian image.

Recommended baseline:

- architecture: x86_64
- disk: enough for `~/Developer`, Nix store, build artifacts, and worktrees
- SSH key: local `~/.ssh/id_ed25519.pub`
- firewall: allow SSH during bootstrap; later restrict to Tailscale if desired

### 2. Bootstrap dotfiles/Home Manager

SSH in as root, then run the existing bootstrap script:

```bash
ssh root@<hetzner-public-ip>

curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap-remote.sh | bash
```

The script currently:

- installs apt basics
- creates `psteinroe`
- installs Determinate Nix
- clones dotfiles
- applies `homeConfigurations."psteinroe@linux-x86_64"`
- installs shared dev tools, including `tailscale` and Linux-only `tmux`

### 3. Ensure SSH access as `psteinroe`

The current bootstrap creates `psteinroe` and a remote outbound SSH key, but it does not yet guarantee that the local Mac key is authorized for inbound SSH as `psteinroe`.

Until bootstrap is enhanced, do this manually:

```bash
sudo -iu psteinroe
mkdir -p ~/.ssh
chmod 700 ~/.ssh
printf '%s\n' '<contents-of-local-~/.ssh/id_ed25519.pub>' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Preferred follow-up: add an optional bootstrap variable such as `AUTHORIZED_KEYS_URL` or `AUTHORIZED_KEYS_TEXT` so this step is reproducible.

### 4. Install and authenticate Tailscale service

Although `tailscale` is in the Home Manager package set, the daemon should be installed/enabled at the OS level on Ubuntu/Debian:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh=false --hostname psteinroe-dev-hetzner
```

Optional unattended variant:

```bash
sudo tailscale up --ssh=false --hostname psteinroe-dev-hetzner --auth-key "$TAILSCALE_AUTHKEY"
```

Use an ephemeral/reusable auth key according to tailnet policy.

### 5. Verify connectivity

From the Mac:

```bash
tailscale status
tailscale ping psteinroe-dev-hetzner
ssh psteinroe@psteinroe-dev-hetzner 'echo ok'
```

If MagicDNS is disabled, use the server's `100.x.y.z` Tailscale IP instead.

### 6. Test wrappers before flipping defaults

Create a temporary SSH host alias, for example:

```sshconfig
Host rdev-hetzner
  HostName psteinroe-dev-hetzner
  User psteinroe
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
```

Then test:

```bash
RDEV_HOST=rdev-hetzner rwtlist hellomateo
RDEV_HOST=rdev-hetzner rdev hellomateo dev
RDEV_HOST=rdev-hetzner rpi hellomateo dev
```

Also run the sustained-output check from the Tailscale plan:

```bash
ssh -T rdev-hetzner 'for i in $(seq 1 60); do date; sleep 1; done'
```

### 7. Flip `rdev` to Hetzner

Once stable, update local `ssh_config` so:

- `rdev` points at the Hetzner Tailscale hostname/IP
- `rdev-exe` remains as exe.dev fallback if still useful
- optionally `rdev-hetzner` remains as an explicit name

Target shape:

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

## Required dotfiles changes

### Bootstrap improvements

Add optional support to `bootstrap-remote.sh` for:

- `AUTHORIZED_KEYS_TEXT`
- `AUTHORIZED_KEYS_URL`
- `INSTALL_TAILSCALE=1`
- `TAILSCALE_AUTHKEY`
- `TAILSCALE_HOSTNAME=psteinroe-dev-hetzner`

The script should:

- install `openssh-server` when apt is available
- authorize inbound SSH for `psteinroe`
- install/enable Tailscale only when requested
- print manual `tailscale up` instructions when no auth key is supplied

### Wrapper simplification

Current `rdev-host` always runs the remote command through:

```bash
sudo -u psteinroe ... /home/psteinroe/.nix-profile/bin/zsh
```

That is compatible if SSHing as root/exedev with passwordless sudo, but unnecessary when connecting directly as `psteinroe`.

Add a compatibility switch such as:

```bash
RDEV_SUDO_USER=psteinroe   # current exe.dev style
RDEV_SUDO_USER=            # direct psteinroe SSH style
```

or detect when the SSH user is already `psteinroe` and skip sudo.

### Docs

Update README remote-dev docs after migration:

- `rdev` uses Hetzner over Tailscale
- `rdev-exe` is fallback/recovery only
- document one-time Tailscale + SSH validation commands

## Security notes

After Tailscale is validated:

- restrict public SSH to trusted IPs or disable it in Hetzner firewall
- keep SSH open on the Tailscale interface
- prefer SSH keys only; disable password login
- consider automatic security updates on Ubuntu/Debian
- keep exe.dev fallback credentials only if they remain useful

## Rollback plan

If Hetzner is broken but exe.dev still exists:

```bash
RDEV_HOST=rdev-exe rdev hellomateo dev
RDEV_HOST=rdev-exe rwtlist hellomateo
ssh rdev-exe
```

If only the `rdev` alias was flipped incorrectly, restore the previous `ssh_config` entry or use `RDEV_HOST=rdev-hetzner`/`RDEV_HOST=rdev-exe` explicitly.

## Acceptance criteria

- `ssh psteinroe@psteinroe-dev-hetzner 'echo ok'` works over Tailscale.
- `rdev hellomateo dev` attaches to remote tmux and stays attached.
- `rwtlist hellomateo` completes without exe.dev.
- `rpi hellomateo dev` runs local Pi with remote tools against Hetzner.
- Sustained-output SSH survives at least 60 seconds over the normal home network.
- `rdev-exe` remains available if exe.dev fallback is retained.

## Open questions

- Final Tailscale hostname: `psteinroe-dev`, `psteinroe-dev-hetzner`, or provider-neutral `rdev`?
- Should bootstrap install Tailscale by default for all generic Linux remotes, or only behind `INSTALL_TAILSCALE=1`?
- Should direct SSH as `psteinroe` become the default wrapper assumption?
- Should public SSH be disabled completely after Tailscale is confirmed?
- Should Hetzner snapshots/backups be enabled for the remote dev disk?
