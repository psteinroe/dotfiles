---
name: subagents
description: Use when the user asks to delegate work to subagents or when independent work can run in parallel.
---

# Subagents

Subagents are headless in-process Pi sessions with separate context windows. They cannot see the parent conversation, ask the user, or spawn more subagents or workflows.

## Delegate

Call `subagent_spawn` with:

- `harness: "pi"` (the only enabled harness)
- a short, recognizable `name`
- a self-contained `prompt` containing the relevant paths, constraints, context, and expected output
- `working_dir` when it differs from the current directory
- optional `model` and `reasoning_effort`; omit both to inherit the parent session

At most four subagents run concurrently. Delegate independent tasks in parallel, then continue useful parent work while they run.

## Manage

- Prefer automatic completion delivery instead of polling.
- Use `subagent_check` for a non-blocking progress check.
- Use `subagent_wait` only when progress depends on the result.
- Use `subagent_list` to inventory all runs.
- Use `subagent_cancel` to stop unnecessary or stuck work.
- Tell the user about `/subagents` when interactive inspection or takeover would help.
