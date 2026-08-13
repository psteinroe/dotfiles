---
name: worktree-agents
description: Create or open dotfiles-layout Git worktrees as Herdr workspaces and launch coding agents in them. Use when the user asks to delegate work to another branch, PR, worktree, or Herdr workspace, or wants an agent working in an isolated checkout. Requires a Herdr-managed pane.
---

# Worktree Agents

Use the dotfiles topology: one repo is one named Herdr session; one Git worktree is one Herdr workspace.

## Choose the topology

- Independent branch or PR work: use this skill to ensure a worktree-backed workspace.
- Work in the current checkout: use a sibling pane in the current workspace, following `herdr --skill`; a second worktree is unnecessary.
- A workspace without a Git worktree is only for non-repository terminal work.

Create a worktree only when the user requested isolated branch/PR/worktree work. Resolve an explicit branch or PR target from the request; ask when it is ambiguous.

## Use the managed helper

Verify the caller is inside Herdr:

```bash
test "${HERDR_ENV:-}" = 1
```

Resolve `scripts/worktree-agent.zsh` relative to this `SKILL.md`. It delegates worktree creation and setup to `hwtcreate` → `wtensure` → `wtsetup`, preserving the `~/Developer/<repo>.git/<worktree>` layout on both local and remote machines.

Use this helper as the only worktree/workspace creation path for project work. Raw `git worktree add`, `herdr worktree create`, and direct project `herdr workspace create` bypass the managed layout and setup.

### Ensure a worktree workspace

```bash
<skill-dir>/scripts/worktree-agent.zsh ensure <branch-or-pr>
```

This is background-safe by default. Add `--focus` only when the user asked to switch to it.

### Launch an agent there

For a short prompt:

```bash
<skill-dir>/scripts/worktree-agent.zsh launch <branch-or-pr> \
  --name <short-agent-name> \
  --prompt '<self-contained task>'
```

For multiline or quote-heavy prompts, write a temporary file and use `--prompt-file <path>`. The default agent kind is `pi`; pass `--kind <kind>` only when the user requests another supported agent. Add `--focus` only when requested.

The launcher opens a fresh tab when the target workspace already exists, so it never takes over an occupied pane. It submits the prompt without waiting, allowing work to continue in parallel.

## Coordinate

Treat the launcher's JSON as the source of truth for the worktree path, workspace ID, pane ID, and unique agent name. Use that returned agent name with current Herdr commands:

```bash
herdr agent get <name>
herdr agent read <name> --source recent-unwrapped --lines 120
herdr agent wait <name> --timeout 120000
```

Run `herdr --skill` when broader Herdr control or current CLI details are needed. Report the launched branch/PR, worktree path, workspace, and agent name to the user.
