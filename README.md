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

### Claude accounts

`agents/claude/accounts.json` lists the Claude Code accounts: `work` uses the
default `~/.claude`, `personal` uses `~/.claude-personal` via
`CLAUDE_CONFIG_DIR`. Each account keeps its own login, settings, history, and
MCP servers; each switch registers executor in every account. In T3 Code, the
default Claude instances use `work` and "Claude Personal" uses `personal`.

Logins stay per machine; they are not copied, because machines sharing one
refresh token log each other out:

```bash
claude-login                                 # this machine; skips logged-in accounts
claude-login --host rdev                     # the remote, over ssh -t
claude-login --host psteinroe@devbox-psteinroe personal
claude-accounts --host rdev                  # who is logged in where
claude-personal                              # Claude Code as the personal account
```

Executor needs one OAuth login per machine and agent as well. `executor-login`
registers it for every Claude account and Codex, skips those already logged in,
and logs in the rest. On a remote it forwards the login's localhost callback and
opens the approval page on this machine:

```bash
executor-login --host psteinroe@devbox-psteinroe   # all Claude accounts and Codex
executor-login --host rdev personal
```

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

## Home hub

A Raspberry Pi 3 at home (`nixosConfigurations.hub`, `nix/nixos/hub/`) runs
[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI), following
[this guide](https://gist.github.com/t3dotgg/59a521d2ee8d70aaf90e280c175072af).
Every Claude and Codex subscription logs in on the hub only; the Mac, rdev, and
the devbox reach it at `https://hub.tail6aabd2.ts.net:8317` (`tailscale serve`,
configured in `zsh/functions/_hub`). The hub lives in the personal tailnet and is
shared into the work tailnet (Tailscale admin: Machines → hub → Share).

Two rules: never serve other people's traffic with these subscriptions, and use
the Claude subscriptions only through Claude Code.

Bootstrap:

1. Run the `pi-images` workflow (Actions → pi-images → Run workflow) and
   download the `hub-sd-image` artifact.
2. `zstd -d nixos-image-*.img.zst`, then flash it with Raspberry Pi Imager or
   `sudo dd if=nixos-image-*.img of=/dev/rdiskN bs=4m`.
3. Boot the Pi on Ethernet and `ssh psteinroe@hub.local` (or its LAN IP).
4. `sudo tailscale up` and log in to the personal tailnet. Enable HTTPS
   certificates in that tailnet's admin (DNS → HTTPS Certificates), then share
   the machine into the work tailnet. `systemctl status cliproxyapi-tailscale-serve`
   finishes once Serve is up.
5. Store the access key in this Mac's Keychain (it is generated on the hub and
   never leaves it otherwise):
   `ssh psteinroe@hub.tail6aabd2.ts.net sudo cat /var/lib/cliproxyapi/access-key`,
   then `set-keychain-environment-variable CLIPROXY_ACCESS_KEY` and paste it.
6. Add accounts, one run per account: `hub-login claude`, `hub-login codex`.
7. Point clients at the hub: `hub-client` (this Mac), `hub-client --host rdev`,
   `hub-client --host psteinroe@devbox-psteinroe`. This writes
   `~/.claude-hub/settings.json` and `~/.codex-hub/config.toml` only; normal
   logins stay. Use `claude-hub` / `codex-hub` in the terminal.
8. Verify: `curl -s https://hub.tail6aabd2.ts.net:8317/v1/models -H "Authorization: Bearer $(keychain-environment-variable CLIPROXY_ACCESS_KEY)" | head -c 300`

The T3 instances "Claude (Hub)" and "Codex (Hub)" in `agents/t3/settings.json`
stay disabled until the hub works; enable them in the T3 UI afterwards. The
management panel is at `/management.html` with the key in
`/var/lib/cliproxyapi/management-key`.

Updates: `scripts/update-cliproxyapi [tag]` pins a new release, `hub-rebuild`
deploys (it evaluates on the Mac and builds or substitutes on the Pi).
`/var/lib/cliproxyapi/config.yaml` is re-rendered from Nix on every service
start, so make config changes in `nix/nixos/hub/cliproxyapi.nix`, not the panel.

## Office connector

The office Tailscale app connector lives in getmateo/devboxes.

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
