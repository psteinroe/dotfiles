# Dotfiles

Cross-platform Nix + Home Manager dev environment.

- macOS: `nix-darwin` + Home Manager
- Linux remotes: standalone Home Manager
- Daily work: [T3 Code](https://github.com/pingdotgg/t3code), on the Mac and against the remote over Tailscale

## Install / update

```bash
# macOS fresh install
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap.sh | bash

# Generic/exe.dev Linux remote fresh install
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap-remote.sh | bash

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
`llm-agents.nix` packages such as Pi, Claude Code, Codex, and tuicr while
leaving arbitrary flake configuration untrusted.

## T3 Code

The Mac runs the T3 Code desktop app (`t3-code` cask). AeroSpace keeps it on
workspace 1 (`alt-enter`); Ghostty floats on its own workspace 3 (`alt-shift-enter`).

Shared configuration:

- `agents/t3/settings.json` is linked into `~/.t3/userdata/settings.json` on
  every machine. Changes made in the T3 UI land in this file as a Git diff.
- Claude Code and Codex come from `llm-agents.nix`; each switch registers the
  executor MCP server for both (add-only, so existing logins stay).
- The machine-wide setup and settle actions run `t3-repo-action`, which executes
  the `runOnWorktreeCreate` / `runOnSettle` scripts in a repo's checked-in
  `t3.json`.

### Remote server

Linux Home Manager owns the pinned T3 Code package and its `systemd --user`
service; T3 owns mutable pairing/provider state in `~/.t3`. Each switch clones
and registers the projects listed in `nix/home/t3code.nix` under
`~/Developer/t3/<repo>` (add-only).

The server binds port 3773 only to the machine's `100.x` Tailscale address.
Traffic is private and encrypted by Tailscale but has no second HTTPS layer:
exe.dev's Tailscale Serve path stalls on the default 1.5-KiB post-quantum TLS
ClientHello. T3 Connect is linked as a fallback route for networks without the
tailnet.

```bash
systemctl --user status t3code
journalctl --user -u t3code -f
systemctl --user restart t3code
```

Generate a fresh one-time link for each new client, then open it in the Mac app
or scan it with the mobile app:

```bash
ssh -t rdev 't3 pair'
```

Pairing tokens are never stored in Nix. Manage or revoke paired sessions under
**Settings → Connections** or with `t3 auth --help`. Update the server only by
changing the pinned Nix version, with `scripts/update-t3code [tag]` (latest
stable release by default); do not use `t3 update` or `t3 service install`.
Server, desktop app, and mobile app must share a major version, so update the
Mac app (`brew upgrade --cask --greedy t3-code`) and the phone at the same time.
Before switching Home Manager across a T3 update, stop the service and make a
versioned backup of `~/.t3`, then start it again after the switch. A Home
Manager rollback restores the binary and unit, but a database-migrating
downgrade also requires the matching state backup.

## Remote machine

- `rdev` → exe.dev machine over Tailscale as `psteinroe`
- `rdev-exe` → exe.dev public SSH fallback as `exedev`

| Command | Purpose |
| --- | --- |
| `rebuild` / `rrebuild [host]` | Rebuild this machine / force-sync dotfiles and rebuild the remote |
| `rssh [dir]` | Plain remote shell |
| `rauth [all\|gh\|pi\|claude\|mcp\|exa\|aws\|gcloud\|azure\|infisical]` | Copy local auth to the remote |
| `ssh rdev-exe` | Recovery path via exe.dev gateway |

Run `devhelp` for the full command list.

## CLIProxy

A Raspberry Pi 3 at home (`nixosConfigurations.cliproxy`, `nix/nixos/cliproxy/`)
runs [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI), following
[this guide](https://gist.github.com/t3dotgg/59a521d2ee8d70aaf90e280c175072af).
It is personal hardware serving personal Claude and Codex subscriptions to the
owner's own machines only; it is not a team credential pool. The accounts log
in on the cliproxy Pi only and their credentials stay there. The API is served
privately on the work tailnet at
`https://cliproxy-psteinroe.tail649856.ts.net:8317` (`tailscale serve`).

This covers the server only: the image, its tailnet setup and adding provider
accounts. No client uses it yet; no Claude Code, Codex, T3 or Pi config here
points at it. A follow-up PR deploys the standard Claude and Codex configs on
the Mac, `rdev` and the devbox so that every consumer there (the plain CLIs, T3,
Pi's bridges where they apply) uses the proxy by default, without per-client
provider logins or account switching. That deployment will also provision the
proxy access key securely, rather than requiring manual edits on each machine.
Initial provider logins on the Pi and occasional provider-required reauthorization
remain necessary.

The setup scales to one independent proxy per team member: each owner runs
their own `cliproxy-<owner>` with their own hardware, `tag:cliproxy-<owner>`
and personal accounts, never a shared service or account pool. Only
`cliproxy-psteinroe` is configured here; this does not provision other members'
instances.

Setup happens once: flash the image, let it join the work tailnet as
`tag:cliproxy-psteinroe`, then authorize your provider accounts in the management
UI. No local provider-login helpers are needed.

The cliproxy Pi joins the work tailnet (the devboxes' one) as
`cliproxy-psteinroe` with `tag:cliproxy-psteinroe`, so that:

- the work Mac (`philipp@hellomateo.de`) reaches the API on 8317 and Tailscale
  SSH on 22;
- the owner's devbox (`tag:devbox-psteinroe`, same tailnet) reaches the API on
  8317 only;
- `rdev`, a user-owned machine of `psteinroe@github` in the personal tailnet,
  reaches the API on 8317 only, through a share of the proxy to that user. That
  user's other devices in the personal tailnet get the same through the share.

Other users and devboxes get no grant, CI has no access to the Pi, and the
proxy itself gets no access to anything else. A share only reaches the user who
accepts it, so it is not a way to reach tagged machines in another tailnet.

Two rules: never serve other people's traffic with these subscriptions, and use
the Claude subscriptions only through Claude Code.

### Tailnet policy

The work tailnet's policy is managed in getmateo/devboxes, never in the admin
console. [devboxes#61](https://github.com/getmateo/devboxes/pull/61) adds the
proxy's narrow rules; merge it before creating its tagged auth key (Bootstrap
step 3). Every proxy has its own owner-scoped `tag:cliproxy-<owner>`, and no tag
or grant spans several owners' proxies. For `tag:cliproxy-psteinroe` it needs:

- `tagOwners` for `tag:cliproxy-psteinroe`;
- grants to `tag:cliproxy-psteinroe`: `philipp@hellomateo.de` on `tcp:8317` and
  `tcp:22`, `tag:devbox-psteinroe` on `tcp:8317`, `autogroup:shared` on
  `tcp:8317` (the proxy is shared only with `psteinroe@github`);
- Tailscale SSH to `tag:cliproxy-psteinroe` as `psteinroe`: `check` for
  `philipp@hellomateo.de`; none for shared users or devboxes;
- no grants with `tag:cliproxy-psteinroe` as source and no app connector grants
  for it, so the proxy's provider traffic leaves from the home connection; no
  other users or devboxes.

`ssh psteinroe@cliproxy-psteinroe.local` on the LAN stays plain OpenSSH.

### Bootstrap

No SSH, no browser login, no commands on the Pi:

1. Run the `pi-images` workflow (Actions → pi-images → Run workflow) and
   download the `cliproxy-sd-image` artifact, or take it from an earlier run.
2. `zstd -d nixos-image-*.img.zst`, then flash the `.img` with Raspberry Pi
   Imager (Use custom, no OS customisation) or balenaEtcher.
3. Once the [policy PR](#tailnet-policy) is merged, create a one-off auth key in
   the work tailnet: Tailscale admin → Settings → Keys → Generate auth key, not
   reusable, not ephemeral, pre-approved if device approval is on, and tagged
   `tag:cliproxy-psteinroe`. Reinsert the SD card and save the key as
   `tailscale-authkey` on its FAT partition (`FIRMWARE`), e.g.
   `pbpaste > /Volumes/FIRMWARE/tailscale-authkey && diskutil eject /Volumes/FIRMWARE`.
4. Put the card in the Pi and plug in Ethernet and power. On first boot it joins
   the work tailnet as `cliproxy-psteinroe` with `--ssh` and
   `tag:cliproxy-psteinroe` and deletes the key file
   (`nix/nixos/pi-tailscale-join.nix`). If it doesn't show up in the admin
   within a few minutes, `ssh psteinroe@cliproxy-psteinroe.local` and
   `journalctl -u tailscale-join`. If the name `cliproxy-psteinroe` is taken,
   use the actual MagicDNS name shown in the admin for the URLs below.

Then:

1. The cliproxy Pi starts `tailscale serve` by itself once the work tailnet has
   HTTPS certificates enabled.
2. Share the proxy (Machines → cliproxy-psteinroe → Share) with
   `psteinroe@github` only and accept the invite as that user, so `rdev` can
   reach the API.
3. On the Mac, open the management UI and add your provider accounts (see
   below).
4. Verify the service (see below).

### Provider accounts

On the Mac, connected to the work tailnet, open the
[management UI](https://cliproxy-psteinroe.tail649856.ts.net:8317/management.html).
Copy its management key to the clipboard without displaying it:

```bash
ssh psteinroe@cliproxy-psteinroe.tail649856.ts.net \
  'cat /var/lib/cliproxyapi/management-key' | pbcopy
```

Paste it into the UI, then use the Claude or Codex OAuth flow for each of your
own accounts. Provider credentials stay on the Pi; add accounts and reauthorize
them here, not on each client. CLIProxyAPI refreshes tokens, round-robins across
eligible accounts and keeps a session on one account. No extra routing settings
are needed for this setup.

Claude and Codex share the same server and API access key, but use their native
API paths: Claude's base URL is the server root (`/v1/messages` requests); Codex's
base URL includes `/v1` (`/v1/responses` requests). Requests use the matching
provider's account pool; adding Codex accounts does not increase Claude quota.
The management key is separate from the API access key used by clients.

### Verify

These checks never print or copy the access key, which is generated on the
cliproxy Pi and stays in `/var/lib/cliproxyapi`:

```bash
# Service up, served on the tailnet, and the logged-in accounts
ssh psteinroe@cliproxy-psteinroe.tail649856.ts.net \
  'systemctl is-active cliproxyapi; sudo tailscale serve status; ls /var/lib/cliproxyapi/auths'
# Reachable over the tailnet and rejects requests without the key: prints 401
curl -s -o /dev/null -w '%{http_code}\n' https://cliproxy-psteinroe.tail649856.ts.net:8317/v1/models
```

The management panel is at `/management.html` with the key in
`/var/lib/cliproxyapi/management-key`.

### Updates

Nothing updates the cliproxy Pi automatically: no CI deploys, no nightly
updater, no reboots by itself. The Pi doesn't compile anything locally
(`nix.settings.max-jobs = 0`). Occasional software and OS updates are still
needed and are done by hand: build the new system elsewhere and switch the Pi to
it, keeping `/var/lib/cliproxyapi` (accounts, keys) and `/var/lib/tailscale`
(tailnet identity). The exact steps are worked out when an update is due.
Reflashing the SD card is not an update path: it wipes those accounts and the
tailnet identity.

To move to another CLIProxyAPI release, edit `cliproxyapiVersion` and the
tarball `hash` in `nix/nixos/cliproxy/cliproxyapi.nix` by hand, then build and
switch as above. `/var/lib/cliproxyapi/config.yaml` is re-rendered from Nix on
every service start, so make config changes in
`nix/nixos/cliproxy/cliproxyapi.nix`, not the panel.

## Office connector

The office Tailscale app connector lives in getmateo/devboxes, and provider
traffic from the devboxes, mine included, still goes through it. That stays
until the cliproxy Pi works and the follow-up client cutover is verified. The
planned cutover is a separate, reviewed devboxes change that removes only
`tag:devbox-psteinroe` from the two office grants; teammates stay routed
through the office. The cliproxy Pi has no connector grants, so its provider
traffic leaves from the home connection.

## Pi models and login

Pi is available as a T3 Code provider and in the terminal. Main and Worker use
`claude-bridge/claude-opus-5-5` with high thinking. Run `/reload` in Pi after
updating the extensions, then `/claude-login` to sign in through the bridge's
Claude Code CLI. This command requires Pi's interactive terminal UI. Claude Code
manages the credentials; Pi's `/login` for Anthropic is separate and does not
authenticate the bridge.

## Git / PR review

| Command | Purpose |
| --- | --- |
| `review` | Open `tuicr` for the current repo |
| `gpd [pr]` | Pipe `gh pr diff` into `diffnav` |
| `gpr [-a] [-n] [-e] [-d] [-f issue]` | Commit/push/create PR helper |
| `gclean` / `greset` | Delete merged branches / reset to the default branch |
| `/pr [--all|-a] [--draft] [--fixes issue]` | Pi PR writer skill |
| `lazygit` | Terminal Git UI |

`diffnav` is the pager for `git diff`; other Git commands use `delta`.

## License

MIT
