---
name: herdr
description: Use inside Herdr when a task needs a branch or PR workspace, even if the request does not name Herdr; also use for explicit Herdr pane, tab, workspace, or persistent-agent operations. Manage project workspaces through the dotfiles helpers. Not for ordinary Pi delegation or background commands. Requires HERDR_ENV=1.
---

# Herdr

## 1. Load the live instructions

Before inspecting or controlling a session, verify that this agent is running inside Herdr:

```bash
test "${HERDR_ENV:-}" = 1
```

If the check fails, explain that this agent must run inside Herdr and stop.

Run `herdr --skill` and follow its current CLI, targeting, coordination, and safety instructions. The installed binary is the authority for Herdr behavior. For project workspace creation, use the managed workflow below instead of its generic workspace/worktree creation examples.

## 2. Choose the managed workflow

Treat any request to create, open, or work in a branch or PR as a workspace request when `HERDR_ENV=1`, even when the user does not mention Herdr. The project convention is one repository per named Herdr session and one Git worktree per workspace. Run helpers from the intended repository in its Herdr session.

| Request | Workflow |
| --- | --- |
| Create or open a branch/PR workspace | `hwtcreate --no-focus <branch-or-pr-number>` |
| Create/open and switch to it | `hwtcreate --focus <branch-or-pr-number>` |
| Expose existing worktrees as workspaces | `hsyncworktrees` |
| Remove stale workspace entries | `hsyncworktrees --prune`, only when requested |
| Inspect/control panes, tabs, or agents | Follow `herdr --skill` |

Invoke the zsh helpers explicitly from Pi's shell tool:

```bash
zsh -lc '
  export RDEV_DOTFILES="${RDEV_DOTFILES:-${LOCAL_DOTFILES:-$HOME/Developer/dotfiles}}"
  source "$RDEV_DOTFILES/zsh/functions/hwtcreate" --no-focus "$1"
' _ <branch-or-pr-number>
```

Replace the placeholder with the requested branch or PR number, passed as a quoted argument. Use `--focus` instead of `--no-focus` only when the user asks to switch.

For synchronization:

```bash
zsh -lc '
  export RDEV_DOTFILES="${RDEV_DOTFILES:-${LOCAL_DOTFILES:-$HOME/Developer/dotfiles}}"
  source "$RDEV_DOTFILES/zsh/functions/hsyncworktrees" "$@"
' _
```

Append `--prune` after `_` only for requested cleanup. This closes stale Herdr workspaces; it does not delete Git worktrees.

Helpers own worktree resolution, setup, and workspace reuse through `wtensure` and `wtsetup`, preserving the managed `~/Developer/<repo>.git/<worktree>` layout. On failure, report the error rather than bypassing them with raw `git worktree add`, `herdr worktree create`, or direct `herdr workspace create` commands.

`hwtcreate` can fetch and update branches through `wtensure`, including rebasing clean divergent branches. Use live Herdr inspection for read-only requests; do not use creation helpers merely to inspect a workspace.

## 3. Continue in the resolved workspace

After helper success, discover live workspace and pane IDs using the CLI. Verify the target workspace and working directory before sending work. The helper's `cd` runs inside the zsh subprocess; subsequent Pi shell calls must explicitly use the resolved worktree directory when needed.

Start a persistent Herdr agent only when the user requested one, in an available shell pane in the resolved workspace, and send its task through the Herdr agent surface. Ordinary delegation uses Pi's `start_subagent`; ordinary long-running commands use `start_background_command`.

Keep focus unchanged unless the user asked to switch.

## 4. Report the result

For workspace operations, report the worktree path, workspace ID, whether it was created or reused, and any agent started. For other operations, report the affected live target and outcome. Include failures or incomplete setup.
