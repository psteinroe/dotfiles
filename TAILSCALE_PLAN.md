# Tailscale Remote Dev Migration Plan

## Goal

Replace the current exe.dev SSH-gateway-based remote development path with a Tailscale-based path, while keeping the user-facing workflow the same:

```bash
rdev hellomateo dev
rwtlist hellomateo
rssh
rpi hellomateo dev
```

There should not be a parallel `rdev-ts` workflow long term. `rdev` should mean “remote dev over the reliable private network”. exe.dev remains the VM provider and bootstrap path, but not the steady-state interactive SSH transport.

## Why

Current evidence points to the exe.dev SSH gateway or the local network path to it resetting sustained interactive SSH streams:

- tmux sessions continue running after local disconnects
- reconnecting shows remote work progressed
- remote machine is not overloaded
- the failure reproduces without tmux using sustained output over SSH
- the same Mac works over phone hotspot
- mobile SSH works

So the issue is below `rdev`/tmux: the Mac/home-network/exe.dev SSH path. Tailscale should route SSH over a WireGuard tunnel and avoid that problematic path.

## exe.dev docs notes

Relevant exe.dev documentation findings:

- exe.dev VMs do **not** get their own public IP. exe.dev handles `ssh vmname.exe.xyz` through its SSH infrastructure.
- exe.dev docs explicitly mention Tailscale as an option for private VM networking.
- Tailscale SSH is optional and independent of exe.dev SSH; it requires `tailscale set --ssh` if we choose to use it.
- exe.dev SSH key docs recommend `IdentitiesOnly yes` and an explicit `IdentityFile` for stable key selection.

Implication: use exe.dev SSH only for bootstrap/recovery. Use Tailscale IP/MagicDNS for normal dev SSH.

## Target architecture

### Before

```text
Mac rdev -> ssh rdev -> psteinroe-dev.exe.xyz -> exe.dev SSH gateway -> VM exedev -> sudo -u psteinroe -> tmux
```

### After

```text
Mac rdev -> ssh rdev -> <tailscale MagicDNS or 100.x IP> -> VM SSH daemon -> exedev -> sudo -u psteinroe -> tmux
```

The wrapper semantics stay the same. Only the `Host rdev` transport changes.

## Naming

Long-term names:

- `rdev`: Tailscale-backed primary remote host
- `rdev-exe`: exe.dev gateway fallback/recovery host

Avoid introducing `rdev-ts` as a permanent command. It is fine as a temporary migration alias if needed, but the final state should make Tailscale the default behind `rdev`.

## SSH config target

Final `ssh_config` shape should be roughly:

```sshconfig
Host exe.dev *.exe.xyz rdev-exe
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519

Host rdev-exe
  HostName psteinroe-dev.exe.xyz
  User exedev
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m

Host rdev
  HostName <tailscale-magicdns-name-or-100.x.y.z>
  User exedev
  IdentitiesOnly yes
  IdentityFile ~/.ssh/id_ed25519
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
```

Notes:

- Keep `User exedev` initially to minimize wrapper changes.
- Existing wrappers already switch to `psteinroe` via `sudo -u psteinroe`.
- If direct `psteinroe` SSH over Tailscale is later made clean, we can simplify wrappers and remove the `exedev -> sudo` hop, but that should be a second step.

## Tailscale setup plan

### Mac

Already partly represented in the repo:

- Homebrew cask: `tailscale-app`
- README has first-time macOS approval notes

Desired checks:

```bash
tailscale status
tailscale ip -4
systemextensionsctl list | rg -i tailscale
```

### Remote VM

Install and enable `tailscaled` on the exe.dev VM.

Because this remote is Ubuntu-ish with Home Manager rather than full NixOS, likely automation belongs in `bootstrap-remote.sh` or a dedicated remote setup script, not in a NixOS `services.tailscale.enable` module.

Possible bootstrap steps:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh=false --hostname psteinroe-dev
```

Auth is intentionally not fully automated unless we provide a Tailscale auth key. Interactive login or a one-time ephemeral auth key is safer.

## Authentication choices

### Option A: plain SSH over Tailscale — preferred first step

Use normal OpenSSH to the VM’s Tailscale address. This preserves existing keys and wrappers.

Pros:

- minimal behavior change
- compatible with current `rdev` implementation
- easy fallback to `rdev-exe`

Cons:

- still needs sshd reachable on the VM’s Tailscale interface

### Option B: Tailscale SSH

Enable Tailscale SSH with:

```bash
sudo tailscale set --ssh
```

Pros:

- identity controlled by Tailscale ACLs
- can reduce SSH key management

Cons:

- different auth model
- requires Tailnet ACL decisions
- may require wrapper/user changes

Recommendation: start with plain SSH over Tailscale. Consider Tailscale SSH only after the transport issue is solved.

## Follow-up: Mosh over Tailscale

Mosh belongs in this Tailscale migration, not the initial Herdr rollout.

### Why here

Mosh needs inbound UDP from client to server. A direct UDP probe to `psteinroe-dev.exe.xyz:60000` timed out, and exe.dev's documented proxy surface is HTTP/TCP-oriented. Therefore Mosh should be validated only after the VM has a working Tailscale address/MagicDNS name.

### What Mosh adds

Use Mosh for roaming/mobile/flaky-network interactive sessions:

- survives laptop sleep/wake and IP changes
- roams across Wi-Fi/cellular/Tailscale path changes
- handles lossy links better than SSH
- can run a remote command such as `herdr --session <repo>`

Constraints:

- requires `mosh` locally and `mosh-server` remotely
- requires UDP over the selected Tailscale path
- is interactive only; it cannot replace non-interactive SSH commands, port forwarding, or Herdr's `--remote` SSH bridge
- running Herdr through Mosh runs the Herdr client on the remote host, so it does not provide Herdr thin-client features like local image clipboard bridging

### Install plan

Add `mosh` to the shared Home Manager package list only after Tailscale is working:

```nix
# Remote connectivity over Tailscale
mosh
```

This should install:

- local `mosh` / `mosh-client` on macOS
- remote `mosh` / `mosh-server` on Linux

### Validation

After Tailscale is authenticated on both ends:

```bash
command -v mosh
ssh rdev 'command -v mosh-server || command -v /home/psteinroe/.nix-profile/bin/mosh-server'
mosh rdev -- true
```

If using a temporary alias before flipping `rdev` to Tailscale:

```bash
mosh <temporary-tailscale-ssh-host> -- true
```

If Mosh reports `Nothing received from the server on UDP port ...`, SSH setup worked but UDP over the chosen path is not working.

### Future helpers

Only after validation, add optional helpers:

```bash
rmherdr <repo> [worktree-or-branch]
rherdr --mosh <repo> [worktree-or-branch]
rmosh [command...]
```

`rmherdr` should reuse the Herdr plan's remote preparation/sync logic, then attach by running Herdr on the remote host as `psteinroe`:

```bash
mosh rdev -- sudo -u psteinroe   HOME=/home/psteinroe USER=psteinroe LOGNAME=psteinroe   PATH=/home/psteinroe/.local/bin:/home/psteinroe/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin   /home/psteinroe/.nix-profile/bin/herdr --session <repo>
```

If `mosh-server` is not on the SSH login user's path, pass it explicitly:

```bash
mosh --server=/home/psteinroe/.nix-profile/bin/mosh-server rdev -- <remote-command>
```

Keep these helpers as follow-ups. Do not make Mosh the default `rdev` path; plain SSH over Tailscale remains the baseline transport for wrappers and non-interactive commands.

## Dotfiles changes to make later

Do **not** do these until ready to migrate.

1. Update `ssh_config`
   - Rename current exe.dev gateway host from `rdev` to `rdev-exe`.
   - Make `Host rdev` point to the Tailscale MagicDNS name or static 100.x IP.
   - Keep explicit key settings.

2. Update docs
   - README Remote Dev Workflow should say `rdev` uses Tailscale.
   - Document `rdev-exe` as recovery/bootstrap only.
   - Add troubleshooting commands for `tailscale status` and `tailscale ping`.

3. Add remote bootstrap support
   - Install tailscale if missing.
   - Start/enable `tailscaled` where systemd exists.
   - Print manual login instructions if no auth key is supplied.
   - Optionally accept `TAILSCALE_AUTHKEY` for unattended setup.

4. Optional helper functions
   - `rdev-exe` helper only if needed for explicit fallback.
   - Avoid `rdev-ts`; Tailscale should be the default `rdev`.

5. Mosh follow-up after Tailscale validation
   - Add `mosh` to shared packages.
   - Add `rmherdr` / `rherdr --mosh` / `rmosh` only after UDP over Tailscale is confirmed.
   - Document Mosh as roaming/mobile interactive attach, not as the default remote transport.

## Migration sequence

1. Install/auth Tailscale on Mac and remote.
2. Verify connectivity:

   ```bash
   tailscale status
   tailscale ping <remote-name>
   ssh exedev@<remote-tailnet-name> 'echo ok'
   ```

3. Verify current wrapper path over Tailscale without changing default:

   ```bash
   RDEV_HOST=<temporary-tailscale-ssh-host> rdev hellomateo dev
   RDEV_HOST=<temporary-tailscale-ssh-host> rwtlist hellomateo
   ```

4. Run sustained-output repro over Tailscale:

   ```bash
   ssh -T <temporary-tailscale-ssh-host> 'for i in $(seq 1 60); do date; sleep 1; done'
   ```

5. Validate Mosh over the same Tailscale path as a follow-up:

   ```bash
   mosh <temporary-tailscale-ssh-host> -- true
   ```

6. If stable, flip defaults:
   - `rdev` -> Tailscale
   - `rdev-exe` -> exe.dev gateway fallback

7. Update README and bootstrap docs.

## Rollback plan

If Tailscale breaks:

```bash
RDEV_HOST=rdev-exe rdev hellomateo dev
RDEV_HOST=rdev-exe rwtlist hellomateo
ssh rdev-exe
```

Keep exe.dev SSH config around permanently as a recovery path.

## Open questions

- What stable Tailscale hostname should the remote use? Suggested: `psteinroe-dev`.
- Should the remote use plain SSH over Tailscale or Tailscale SSH long term?
- Should direct SSH as `psteinroe` replace the current `exedev -> sudo -u psteinroe` pattern?
- Do we want unattended bootstrap via `TAILSCALE_AUTHKEY`, and where should that secret live?
- Should `rpi` also default to Tailscale once `rdev` does?
- Should Mosh helpers be added once Tailscale UDP works, or kept as manual commands?
- Should Mosh use the default UDP range `60000-61000`, or should wrappers pass a narrower range?

## Acceptance criteria

- `rdev hellomateo dev` attaches and stays attached over normal home network.
- `rwtlist hellomateo` no longer drops during tmux attach.
- Sustained-output SSH repro survives for at least 60 seconds over normal network.
- `rdev-exe` remains available for recovery.
- README documents Tailscale as the primary transport and exe.dev SSH as fallback.
- Follow-up Mosh validation over Tailscale is documented and either passes or records why UDP is unavailable.
