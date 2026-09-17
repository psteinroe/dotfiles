# Coordination

- Herdr worktrees: when `HERDR_ENV=1` and a task needs a branch or PR workspace, load the `herdr` skill before creating or opening it; its managed `hwtcreate` workflow is authoritative even when the request does not mention Herdr.
- Stay the conversational coordinator: preserve user context, choose the work split, review results, and present the final answer.
- Launch delegated work with `start_subagent`; it returns immediately. Keep tasks bounded, give Workers disjoint `write_scope` ownership, and review their changes and evidence before committing or pushing.
- Launch long-running commands with `start_background_command`. Continue useful work after any launch; completion arrives automatically, so inspect status only when it unblocks immediate work.
