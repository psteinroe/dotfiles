# Herdr Workflow

Current state: this repo is Herdr-first and Pi-only.

## Model

- One Herdr named session per repo/project.
- One Herdr workspace per Git worktree.
- Worktree layout stays `~/Developer/<repo>.git/<worktree>`.
- Local entrypoint: `hdev <repo> [worktree|branch|pr]`.
- Remote entrypoint: `rdev <repo> [worktree|branch|pr]` over Tailscale SSH.
- Remote rebuild entrypoint: `rrebuild [host]`.

## Remote transport

- `rdev` logs in directly as `psteinroe` over Tailscale.
- `rdev-exe` remains only a bootstrap/recovery SSH target.
- Native Herdr remote attach is the steady-state path:

```bash
herdr --remote rdev --session <repo>
```

## Helpers

- `hprepare <repo> [worktree]` prepares/focuses the Herdr session/workspace.
- `hdev <repo> [worktree]` prepares locally, then attaches Herdr.
- `rdev <repo> [worktree]` prepares remotely, then attaches native Herdr remote.
- `hsyncworktrees [--prune]` syncs current Git worktrees into Herdr workspaces.
- `hwtcreate <branch|pr>` ensures a worktree and opens/focuses its Herdr workspace.
- `rwtclean <repo>` / `rwtforceclean <repo>` remain cleanup-only remote helpers.

## Agent integration

Pi is the only managed coding-agent integration.

- Home Manager installs Pi from `llm-agents.nix`.
- `agents/pi/**` is linked into `~/.pi/agent`.
- Shared skills under `agents/skills/**` are deployed to Pi.
- Herdr installs only the Pi integration.

## Cleanup behavior

- `wtclean` and `wtforceclean` close matching Herdr workspaces by exact cwd/path before removing worktrees.
- Cleanup is best-effort for Herdr and must not block Git cleanup.
- No label-only Herdr workspace cleanup.

## Keybindings

- Prefix: `Ctrl+B`.
- Detach: `Ctrl+B q` / `Ctrl+B d`.
- Reload config: `Ctrl+B Shift+R`.
- Worktree manager: `Ctrl+B Shift+M`.
- Sync worktrees: `Ctrl+B Shift+S`.
- Create/open worktree: `Ctrl+B Shift+G`.
- Open existing worktree: `Ctrl+B Shift+O`.
- Hide workspace: `Ctrl+B Shift+H`.
- Bootstrap panes: `Ctrl+B Shift+B`.
- Seamless Neovim/Herdr navigation: raw `Ctrl+H/J/K/L`.

## Validation

Useful checks:

```bash
nix flake check
zsh -n zsh/functions/rdev zsh/functions/hdev zsh/functions/hprepare
herdr plugin action list --plugin psteinroe.worktree-sync
herdr integration status
hdev dotfiles main
rdev dotfiles main
```
