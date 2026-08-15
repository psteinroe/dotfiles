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

### Launch a worker there

The coordinating main agent is the review gate. Before delegation, verify it is GPT-5.6 Sol at high thinking:

```bash
test "${PI_PROVIDER:-}" = openai-codex
test "${PI_MODEL:-}" = gpt-5.6-sol
test "${PI_REASONING_LEVEL:-}" = high
```

Ask the user to switch the main session when this gate fails. Launch the worker with a self-contained task and checkable acceptance criteria:

```bash
<skill-dir>/scripts/worktree-agent.zsh launch <branch-or-pr> \
  --name <short-agent-name> \
  --prompt '<self-contained task and acceptance criteria>'
```

Pi workers default to GPT-5.6 Terra at high thinking. Use `--model <provider/model>` only for deliberate routing. For multiline or quote-heavy prompts, write a temporary file and use `--prompt-file <path>`. Pass `--kind <kind>` only when the user requests another supported agent. Add `--focus` only when requested.

The launcher keeps one live agent per worktree. It reuses an idle or done worker only when its Pi model and thinking level match the request, and refuses a second launch while that worktree's agent is working, blocked, or unknown. Independent worktrees can continue in parallel.

## Review loop

Treat the launcher's JSON as the source of truth for the worktree path, workspace ID, pane ID, agent name, model, and review requirement.

1. Wait for the worker to settle. A wait timeout means inspect and wait again, not that the task is complete.
2. Read the worker output for orientation. Treat its claims as unverified.
3. Independently inspect all committed, staged, unstaged, and untracked changes from the returned worktree path. Run the relevant tests, type checks, lint, build, or other project validation there.
4. If review finds defects or unverified requirements, call `launch` again for the same target with a focused correction prompt. The launcher reuses the settled worker. Wait and repeat the independent review.
5. Report completion only after the main agent finds no actionable defects and has fresh validation evidence for every acceptance criterion.

Use current Herdr commands to coordinate:

```bash
herdr agent get <name>
herdr agent read <name> --source recent-unwrapped --lines 120
herdr agent wait <name> --timeout 120000
```

Run `herdr --skill` when broader Herdr control or current CLI details are needed. Delegation is not complete when the worker stops; it is complete only after the main-agent review gate passes. Report the branch/PR, worktree path, worker model, review rounds, findings resolved, and final validation evidence.
