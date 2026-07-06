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

Project shortcuts follow the same local/remote pattern: `dotfiles` / `rdotfiles`, `hellomateo` / `rhellomateo`, `sbch` / `rsbch`, `pgls` / `rpgls`, `pgconductor` / `rpgconductor`, and `toolshed` / `rtoolshed`.

Local and remote helpers intentionally mirror each other where possible:

| Local | Remote | Purpose |
| --- | --- | --- |
| `rebuild` | `rrebuild [host]` | Rebuild this machine / pull dotfiles and rebuild remote Home Manager |
| `hdev <repo> [branch\|pr]` | `rdev <repo> [branch\|pr]` | Open local/remote Herdr project session |
| `wtclean` | `rwtclean <repo>` | Clean merged/closed worktrees |
| `wtforceclean` | `rwtforceclean <repo>` | Select and force-remove worktrees |
| `hwtcreate <branch\|pr>` | `rhwtcreate <repo> <branch\|pr>` | Ensure worktree and focus/open Herdr workspace |
| `hsyncworktrees [--prune]` | `rhsyncworktrees <repo> [--prune]` | Sync Git worktrees into Herdr workspaces |
| — | `rauth [all\|gh\|pi\|mcp\|exa]` | Copy local GitHub/Pi/MCP/Exa auth to the remote |
| — | `ssh rdev-exe` | Recovery path via exe.dev gateway |

For the full command list, run `devhelp`.

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
