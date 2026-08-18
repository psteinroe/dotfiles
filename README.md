# Dotfiles

Cross-platform Nix + Home Manager dev environment.

- macOS: `nix-darwin` + Home Manager
- Linux remotes: standalone Home Manager
- Remote dev: Tailscale SSH + Herdr-first project sessions

## Install / update

```bash
# macOS fresh install
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap.sh | bash

# Linux remote fresh install
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
`llm-agents.nix` packages such as Pi, tuicr, and Herdr while leaving arbitrary
flake configuration untrusted.

## Daily project workflow

One project/repo maps to one Herdr named session. One Git worktree maps to one Herdr workspace.

```bash
hdev dotfiles main       # local Herdr session/workspace
rdev hellomateo main     # remote Herdr over Tailscale
hellomateo main          # shortcut for hdev hellomateo main
rhellomateo main         # shortcut for rdev hellomateo main
```

Remote defaults:

- `rdev` → Tailscale SSH as `psteinroe`
- `rdev-exe` → exe.dev SSH fallback as `exedev`
- Worktrees stay at `~/Developer/<repo>.git/<worktree>`

### Moshi mobile access

Home Manager installs Mosh and a pinned `moshi-hook`, runs the hook as a
persistent systemd user service, and exposes the managed Herdr sessions to
Moshi. For the primary mobile connection, install Tailscale on the phone and
use:

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
`~/.ssh/authorized_keys`, and the Mosh server is exposed on the non-interactive
SSH path. Agent notification pairing remains a one-time secret-bearing step:

```bash
moshi-hook pair --token <token-from-Moshi> --store file
systemctl --user restart moshi-hook
```

The public exe.dev route remains an SSH-only fallback: connect to
`psteinroe-dev.exe.xyz` as `exedev` and force **SSH** because the gateway does
not proxy Mosh UDP traffic. Global Herdr and `moshi-hook` bridges transparently
run those integrations as `psteinroe` on that fallback connection.

Project shortcuts follow the same local/remote pattern: `dotfiles` / `rdotfiles`, `hellomateo` / `rhellomateo`, `ceplatform` / `rceplatform`, `radiomarl` / `rradiomarl`, `ninjascale` / `rninjascale`, `sbch` / `rsbch`, `pgls` / `rpgls`, `pgconductor` / `rpgconductor`, `pgstream` / `rpgstream`, `hpgstream` / `rhpgstream`, and `toolshed` / `rtoolshed`.

Local and remote helpers intentionally mirror each other where possible:

| Local | Remote | Purpose |
| --- | --- | --- |
| `rebuild` | `rrebuild [host]` | Rebuild locally/remotely, then reload resources in idle Pi agents |
| `hdev <repo> [branch\|pr]` | `rdev <repo> [branch\|pr]` | Open local/remote Herdr project session |
| `wtclean` | `rwtclean <repo>` | Clean integrated/stale worktrees |
| `wtforceclean` | `rwtforceclean <repo>` | Select and force-remove worktrees |
| `hwtcreate <branch\|pr>` | `rhwtcreate <repo> <branch\|pr>` | Ensure worktree and focus/open Herdr workspace |
| `hsyncworktrees [--prune]` | `rhsyncworktrees <repo> [--prune]` | Sync Git worktrees into Herdr workspaces |
| — | `rauth [all\|gh\|pi\|mcp\|exa]` | Copy local GitHub/Pi/MCP/Exa auth to the remote |
| — | `ssh rdev-exe` | Recovery path via exe.dev gateway |

For the full command list, run `devhelp`. Rebuilds invoke `pireload`, which reloads only idle Pi agents with no child processes. Working, blocked, and background-task sessions are reported and left untouched; retry from the `Safe Pi Reload` Herdr action or run `pireload` later.

Pi also receives the `worktree-agents` skill on local and remote machines. When
asked to delegate work into another branch, PR, or worktree, it routes creation
through `hwtcreate`/`wtensure` and starts the agent in the matching Herdr
workspace instead of using Herdr's default worktree layout. Agent launches keep
the current workspace focused unless explicitly asked to switch.

## Git worktrees

```bash
wtclone git@github.com:user/repo.git
cd repo.git/main
wtcreate feature-x
wtcheckout 123
wtclean
```

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
