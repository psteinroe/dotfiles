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
MCP servers; each switch registers executor in every account. T3 Code has one
Claude instance per account (Claude Work, Claude Personal).

Logins stay per machine; they are not copied, because machines sharing one
refresh token log each other out:

```bash
claude-login                                 # this machine; skips logged-in accounts
claude-login --host rdev                     # the remote, over ssh -t
claude-login --host psteinroe@devbox-psteinroe personal
claude-accounts --host rdev                  # who is logged in where
claude-personal                              # Claude Code as the personal account
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
