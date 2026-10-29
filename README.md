# Dotfiles

Cross-platform Nix + Home Manager dev environment.

- macOS: `nix-darwin` + Home Manager
- Linux remotes: standalone Home Manager
- Remote dev: Tailscale SSH + Herdr-first project sessions

## Install / update

```bash
# macOS fresh install
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap.sh | bash

# Generic/exe.dev Linux remote fresh install
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap-remote.sh | bash

# Prepared Hetzner NixOS replacement (review before destructive use)
# See docs/hetzner-nixos.md and ./bootstrap-hetzner-nixos.sh

# Update an existing machine
rebuild
```

Manual builds:

```bash
# macOS
nix run nix-darwin -- switch --flake ~/Developer/dotfiles#psteinroe

# Linux remote
nix run nixpkgs#home-manager -- switch --flake ~/Developer/dotfiles#psteinroe@linux-x86_64
```

The bootstrap and nix-darwin configuration manage Determinate Nix's
`/etc/nix/nix.custom.conf`. It trusts Numtide's binary cache for prebuilt
`llm-agents.nix` packages such as Pi, tuicr, and Herdr while leaving arbitrary
flake configuration untrusted.

### T3 Code remote access

Linux Home Manager declaratively owns the pinned T3 Code package and its
`systemd --user` service; T3 owns mutable pairing/provider state in `~/.t3`.
It does not use T3 Connect or Tailscale Funnel. Nix Darwin installs the
`t3-code` desktop app on the Mac.

The standalone Linux profile used by exe.dev binds port 3773 only to the
machine's dynamic `100.x` Tailscale address. Traffic is private and encrypted
by Tailscale, but it intentionally has no second HTTPS layer. This avoids a
Tailscale Serve/netstack failure on exe.dev where the default 1.5-KiB
post-quantum TLS ClientHello stalls; TLS 1.2 and TLS 1.3 forced to X25519 both
succeed, as does the same default TLS handshake to a normal Go server over the
same tailnet path. The prepared Hetzner NixOS profile uses private Tailscale
Serve HTTPS, subject to the TLS 1.3 acceptance check in
[`docs/hetzner-nixos.md`](docs/hetzner-nixos.md).

```bash
systemctl --user status t3code
journalctl --user -u t3code -f
systemctl --user restart t3code
```

The Mac and phone must be connected to the existing tailnet. Generate a fresh
one-time link on the host for each client, then open it in the Mac app or scan
it with the mobile app:

```bash
# Current exe.dev direct-tailnet transport
ssh -t rdev 't3 pair'

# Future Hetzner private HTTPS transport
ssh -t rdev-hetzner 't3 pair --tailscale'
```

Pairing tokens are never stored in Nix. Manage or revoke paired sessions under
**Settings → Connections** or with `t3 auth --help`. Update the server only by
changing the pinned Nix version, with `scripts/update-t3code [tag]` (latest
stable release by default); do not use `t3 update` or `t3 service install`.
Server, desktop app, and mobile app must share a major version, so update the
Mac app (`brew upgrade --cask --greedy t3-code`) and the phone at the same time. Before switching Home Manager, stop the service and make
a versioned backup of `~/.t3`, then start it again after the switch. A Home
Manager rollback restores the binary and unit, but a database-migrating
downgrade also requires the matching state backup. Removing `~/.t3` is a full
reset that requires pairing every client again. When switching exe.dev from
Serve to direct mode, remove any stale mapping with
`tailscale serve --https=443 off`.

## Daily project workflow

One project/repo maps to one Herdr named session. The active-workspace policy is
agent-first: Herdr starts with its sidebar hidden and agent panel sorted by
priority, and only the selected/requested Git worktree is opened as a workspace.
Other worktrees remain available in Git but are not materialized in Herdr until
opened explicitly. Use `prefix+b` to toggle the sidebar and `prefix+w` to pick a
workspace; `alt+h`/`alt+l` switch workspaces and `alt+k`/`alt+j` switch agents.

```bash
hdev dotfiles main       # local Herdr session/workspace
rdev hellomateo main     # prepare/register remote session, then return
hellomateo main          # shortcut for hdev hellomateo main
rhellomateo main         # shortcut for rdev hellomateo main
rhops main               # shortcut for rdev operations-platform main
```

Remote defaults:

- `rdev` → current exe.dev machine over Tailscale as `psteinroe`
- `rdev-hetzner` → prepared NixOS replacement's future MagicDNS name
- `rdev-exe` → exe.dev public SSH fallback as `exedev`
- Worktrees stay at `~/Developer/<repo>.git/<worktree>`

The full Hetzner install, validation, cutover, and recovery runbook is in
[`docs/hetzner-nixos.md`](docs/hetzner-nixos.md). `rdev` is not switched until
the new host passes those checks.

There is one local Herdr client. `rdev <repo> [branch|pr]` SSHes to the remote,
prepares the named session, and returns; it does not open a second remote TUI.
Identity is the target plus session (`<host>` and `<repo>`), not the label.
New profiles use the canonical `<host>/<repo>` label, while existing labels are
preserved when their target/session profile is reused. Profiles are refreshed
live in the Herdr client. `rherdr <repo> [branch|pr]` remains the explicit
direct remote attach for recovery.

### Moshi mobile access

Home Manager installs Mosh and a pinned `moshi-hook`, runs the hook as a
persistent systemd user service, and exposes the managed Herdr sessions to
Moshi. Moshi remains independent of the local Herdr client and connects
directly to the named remote session. For the primary mobile connection,
install Tailscale on the phone and use:

- Host: `psteinroe-dev.tail6aabd2.ts.net`
- Port: `22`
- User: `psteinroe`
- Connection type: **Mosh** or **Auto**

As `psteinroe`, run the following and scan its Easy Pair QR in Moshi:

```bash
moshi-hook host setup \
  --host psteinroe-dev.tail6aabd2.ts.net \
  --user psteinroe
```

The exe.dev SSH configuration accepts the generated key from
`~/.ssh/authorized_keys`, and the Mosh server is exposed on the non-TUI
SSH path. Agent notification pairing remains a one-time secret-bearing step:

```bash
moshi-hook pair --token <token-from-Moshi> --store file
systemctl --user restart moshi-hook
```

The public exe.dev route remains an SSH-only fallback: connect to
`psteinroe-dev.exe.xyz` as `exedev` and force **SSH** because the gateway does
not proxy Mosh UDP traffic. Global Herdr and `moshi-hook` bridges transparently
run those integrations as `psteinroe` on that fallback connection.

Project shortcuts follow the same local/remote pattern: `dotfiles` / `rdotfiles`, `hellomateo` / `rhellomateo`, `hops` / `rhops`, `ceplatform` / `rceplatform`, `radiomarl` / `rradiomarl`, `ninjascale` / `rninjascale`, `sbch` / `rsbch`, `pgls` / `rpgls`, `pgconductor` / `rpgconductor`, `pgstream` / `rpgstream`, `hpgstream` / `rhpgstream`, and `toolshed` / `rtoolshed`.

Local and remote helpers intentionally mirror each other where possible:

| Local | Remote | Purpose |
| --- | --- | --- |
| `rebuild` | `rrebuild [host]` | Rebuild locally/remotely, then reload resources in idle Pi agents |
| `hdev <repo> [branch\|pr]` | `rdev <repo> [branch\|pr]` | Open locally, or prepare/register remote session and return to the Herdr client |
| `wtclean` | `rwtclean <repo>` | Clean integrated/stale worktrees |
| `wtforceclean` | `rwtforceclean <repo>` | Select and force-remove worktrees |
| `hwtcreate <branch\|pr>` | `rhwtcreate <repo> <branch\|pr>` | Ensure requested worktree and focus/open its workspace |
| `htrimworkspaces [--apply\|--auto]` | — | Preview/confirm, or automatically close only strictly safe idle siblings |
| `hsyncworktrees [--prune\|--prune-only]` | `rhsyncworktrees <repo> [--prune]` | Explicitly expose all worktrees, or prune stale Herdr workspaces |
| — | `rauth [all\|gh\|pi\|claude\|mcp\|exa\|aws\|gcloud\|azure\|infisical]` | Copy local GitHub/Pi/Claude Bridge/MCP/Exa/AWS/gcloud/Azure/Infisical auth to the remote |
| — | `ssh rdev-hetzner` | Test the prepared Hetzner NixOS replacement before cutover |
| — | `ssh rdev-exe` | Recovery path via exe.dev gateway |

For the full command list, run `devhelp`. `rhwtcreate` and `rhsyncworktrees`
use `rdev` preparation/registration without a second TUI when their remote
session is absent. First-time machine add may perform SSH/bootstrap
compatibility setup and prompt. `rherdr` is reserved for direct
recovery/Moshi attachment. Normal preparation and the worktree
hook only prune stale/missing Herdr workspaces and open the requested target;
there is no bulk workspace sync. `hsyncworktrees` without an option (or with
`--prune`) is the manual **expose all worktrees** escape hatch, not normal
maintenance. `--prune-only` is the safe cleanup mode. `htrimworkspaces` previews
idle candidates and, with `--apply`, asks for confirmation while protecting
focused workspaces, agents, dirty Git worktrees, non-shell processes,
background/descendant processes, and uncertain inspections. Opening a worktree
automatically runs the same strict cleanup for sibling workspaces: only clean,
shell-idle siblings can close; Git worktrees, focused workspaces, agents, dirty
files, active commands, background/descendant jobs, and uncertain states are
preserved. Closing a Herdr workspace never deletes its Git
worktree.

Rebuilds invoke `pireload`, which reloads only idle Pi agents with no child
processes. Working, blocked, and background-task sessions are reported and left
untouched; retry from the `Safe Pi Reload` Herdr action or run `pireload` later.

Pi also receives the `herdr` skill on local and remote machines. It activates
only when the user explicitly asks Pi to control Herdr. Project workspace creation routes through `hwtcreate`/`wtensure` instead of
Herdr's default worktree layout and keeps the current workspace focused unless
asked to switch. The worktree manager's `t` action runs the interactive trim helper; opening an
existing worktree also runs the non-interactive strict cleanup. Its `s` action is
the explicit full-sync escape hatch. Closing a workspace preserves the underlying
Git worktree.
Pi's internal subagents continue to use their normal runtime rather than Herdr
workspaces.

## Home hub

A Raspberry Pi 3 at home (`nixosConfigurations.hub`, `nix/nixos/hub/`) runs
[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI), following
[this guide](https://gist.github.com/t3dotgg/59a521d2ee8d70aaf90e280c175072af).
It is personal hardware serving personal Claude and Codex subscriptions to the
owner's own machines only; it is not a team credential pool. The accounts log
in on the hub only, and clients reach it at `https://hub.tail649856.ts.net:8317`
(`tailscale serve`, configured in `zsh/functions/_hub`).

Setup happens once: flash the image, let it join the work tailnet as `tag:hub`,
log in each of your own provider accounts with repeated `hub-login`, point the
Mac, `rdev` and your devbox at it with `hub-client`, then use the isolated
aliases.

The hub joins the work tailnet (the devboxes' one) as `tag:hub`, so that:

- the work Mac (`philipp@hellomateo.de`) reaches the API on 8317 and Tailscale
  SSH on 22;
- the owner's devbox (`tag:devbox-psteinroe`, same tailnet) reaches the API on 8317
  only;
- `rdev`, a user-owned machine of `psteinroe@github` in the personal tailnet,
  reaches the API on 8317 only, through a share of the hub to that user. That
  user's other devices in the personal tailnet get the same through the share.

Other users and devboxes get no grant, CI has no access to the Pi, and the hub
itself gets no access to anything else. A share only reaches the user who
accepts it, so it is not a way to reach tagged machines in another tailnet.

Two rules: never serve other people's traffic with these subscriptions, and use
the Claude subscriptions only through Claude Code.

### Tailnet policy

The work tailnet's policy is managed in getmateo/devboxes, never in the admin
console. [devboxes#61](https://github.com/getmateo/devboxes/pull/61) adds the hub's
narrow rules; merge it before creating the hub's tagged auth key (Bootstrap
step 3). It needs:

- `tagOwners` for `tag:hub`;
- grants to `tag:hub`: `philipp@hellomateo.de` on `tcp:8317` and `tcp:22`,
  `tag:devbox-psteinroe` on `tcp:8317`, `autogroup:shared` on `tcp:8317` (the
  hub is shared only with `psteinroe@github`);
- Tailscale SSH to `tag:hub` as `psteinroe`: `check` for
  `philipp@hellomateo.de`; none for shared users or devboxes;
- no grants with `tag:hub` as source and no app connector grants for it, so the
  hub's provider traffic leaves from the home connection; no other users or
  devboxes.

`ssh psteinroe@hub.local` on the LAN stays plain OpenSSH.

### Bootstrap

No SSH, no browser login, no commands on the Pi:

1. Run the `pi-images` workflow (Actions → pi-images → Run workflow) and
   download the `hub-sd-image` artifact, or take it from an earlier run.
2. `zstd -d nixos-image-*.img.zst`, then flash the `.img` with Raspberry Pi
   Imager (Use custom, no OS customisation) or balenaEtcher.
3. Once the [policy PR](#tailnet-policy) is merged, create a one-off auth key in
   the work tailnet: Tailscale admin → Settings → Keys → Generate auth key, not
   reusable, not ephemeral, pre-approved if device approval is on, and tagged
   `tag:hub`. Reinsert the SD card and save the key as `tailscale-authkey` on its
   FAT partition (`FIRMWARE`), e.g.
   `pbpaste > /Volumes/FIRMWARE/tailscale-authkey && diskutil eject /Volumes/FIRMWARE`.
4. Put the card in the Pi and plug in Ethernet and power. On first boot it joins
   the work tailnet as `hub` with `--ssh` and `tag:hub` and deletes the key file
   (`nix/nixos/pi-tailscale-join.nix`). If it doesn't show up in the admin
   within a few minutes, `ssh psteinroe@hub.local` and
   `journalctl -u tailscale-join`. If the name `hub` is taken it gets another
   one; set `HUB_URL` to match.

Then:

1. The hub starts `tailscale serve` by itself once the work tailnet has HTTPS
   certificates enabled; `systemctl status cliproxyapi-tailscale-serve` finishes
   when it is up.
2. Share the hub (Machines → hub → Share) with `psteinroe@github` only and
   accept the invite as that user, so `rdev` can reach the API.
3. Store the access key in the work Mac's Keychain (it is generated on the hub
   and otherwise never leaves it):
   `ssh psteinroe@hub.tail649856.ts.net sudo cat /var/lib/cliproxyapi/access-key`,
   then `set-keychain-environment-variable CLIPROXY_ACCESS_KEY` and paste it.
4. On the Mac, add the accounts, one `hub-login` run per account (see below).
5. Point each machine at the hub with `hub-client` (see below).
6. Verify: `curl -s https://hub.tail649856.ts.net:8317/v1/models -H "Authorization: Bearer $(keychain-environment-variable CLIPROXY_ACCESS_KEY)" | head -c 300`

### `hub-login` vs `hub-client`

`hub-login` adds a subscription account to the hub. It runs on the Mac, opens
the provider's login there, and runs CLIProxyAPI's login on the hub over
Tailscale SSH, so the new OAuth credentials are created and stored on the hub
only. Only the Mac has SSH to the hub; `rdev` and the devbox use the API only, so
run every login from the Mac. Repeat it for each of your own accounts;
CLIProxyAPI round-robins across them and keeps a session on one account.

```bash
hub-login claude   # personal Claude account, browser OAuth (callback port forwarded to the hub)
hub-login codex    # personal ChatGPT account, device code
```

`hub-client` points a machine at the hub. It writes only the isolated
`~/.claude-hub/settings.json` and `~/.codex-hub/config.toml` with the hub's URL
and access key. The key goes from the Mac's Keychain over stdin (through ssh for
`--host`), never in arguments. Normal `~/.claude` and `~/.codex` logins stay
untouched, and no OAuth credential is ever copied off the hub.

```bash
hub-client                                    # the Mac
hub-client --host rdev                        # rdev, through the share
hub-client --host psteinroe@devbox-psteinroe  # the owner's devbox
```

Then use `claude-hub` / `codex-hub` on that machine, or the T3 instances
"Claude (Hub)" and "Codex (Hub)" in `agents/t3/settings.json`; they stay
disabled until the hub works, enable them in the T3 UI afterwards. The
management panel is at `/management.html` with the key in
`/var/lib/cliproxyapi/management-key`.

### Updates

Nothing updates the hub automatically: no CI deploys, no nightly updater, no
reboots by itself. The Pi doesn't compile anything locally
(`nix.settings.max-jobs = 0`). Occasional software and OS updates are still
needed and are done by hand: build the new system elsewhere and switch the Pi to
it, keeping `/var/lib/cliproxyapi` (accounts, keys) and `/var/lib/tailscale`
(tailnet identity). The exact steps are worked out when an update is due.
Reflashing the SD card is not an update path: it wipes those accounts and the
tailnet identity.

`scripts/update-cliproxyapi [tag]` optionally bumps the pinned CLIProxyAPI
release in `nix/nixos/hub/cliproxyapi.nix`; it only edits the pin and deploys
nothing. `/var/lib/cliproxyapi/config.yaml` is re-rendered from Nix on every
service start, so make config changes in `nix/nixos/hub/cliproxyapi.nix`, not
the panel.

## Office connector

The office Tailscale app connector lives in getmateo/devboxes, and provider
traffic from the devboxes, mine included, still goes through it. That stays
until the hub is online, its logins work and the clients above are verified.
The planned cutover is a separate, reviewed devboxes change that removes only
`tag:devbox-psteinroe` from the two office grants; teammates stay routed
through the office. The hub has no connector grants, so its provider traffic
leaves from the home connection.

## Pi models and login

Main and Worker use `claude-bridge/claude-opus-5-5` with high thinking.
Run `/reload` in Pi after updating the extensions, then `/claude-login` to
sign in through the bridge's Claude Code CLI. This command requires Pi's
interactive terminal UI. Claude Code manages the credentials; Pi's `/login`
for Anthropic is separate and does not authenticate the bridge.

## Git worktrees

```bash
wtclone git@github.com:user/repo.git
cd repo.git/main
wtcreate feature-x
wtcheckout 123
wtclean
```

`wtclean` / `rwtclean` **delete worktree directories**, including ignored files;
use `htrimworkspaces` when you only want to close idle workspaces. Cleanup asks
for confirmation, protects live agents, and skips candidates whose Git status,
agent state, or filesystem permissions cannot be verified. It requires Python
3.8+, Herdr, and jq for read-only preflight and agent checks, including ignored
directories and nested mounts on Linux. Permission blockers require manual review: cleanup never runs
`sudo`, `chown`, or `chmod` to bypass them. Existing unregistered leftovers are
not force-deleted.

Clean candidates are removed without `--force`. Stale local changes require
explicit confirmation and must still be older than `WTCLEAN_STALE_DAYS` (default
7) after confirmation. Branch, commit, dirty state, agent state, and filesystem
permissions are rechecked before removal; stale-dirty contents are fingerprinted
so preserved timestamps cannot conceal new work. These checks reduce risk but are not
atomic: Git deletion can still partially fail if the filesystem or another
process changes after preflight. Unrelated Herdr workspaces are not globally
pruned, and tmux sessions are not killed by cleanup.

Common local commands:

| Command | Purpose |
| --- | --- |
| `wtclone <url>` | Clone as bare repo plus `main` worktree |
| `wtcreate <branch>` | Create branch worktree |
| `wtcheckout <branch\|pr#>` | Checkout branch/PR worktree |
| `wtensure <branch\|pr#>` | Ensure worktree exists and cd into it |

## Git / PR review

| Command | Purpose |
| --- | --- |
| `review` | Open `tuicr` for the current repo |
| `gpd [pr]` | Pipe `gh pr diff` into `diffnav` |
| `gpr [-a] [-n] [-e] [-d] [-f issue]` | Commit/push/create PR helper |
| `/pr [--all|-a] [--draft] [--fixes issue]` | Pi PR writer skill |
| `lazygit` | Terminal Git UI |

`diffnav` is the pager for `git diff`; other Git commands use `delta`.

## License

MIT
