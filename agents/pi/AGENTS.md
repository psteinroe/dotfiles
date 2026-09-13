# Coordination

- Herdr worktrees: when `HERDR_ENV=1` and a task needs a branch or PR workspace, load the `herdr` skill before creating or opening it; its managed `hwtcreate` workflow is authoritative even when the request does not mention Herdr.
- Stay the conversational coordinator: preserve user context, choose the work split, review results, and present the final answer.
- Parallelize independent work with disjoint file ownership. Keep delegated tasks bounded, and review their changes and evidence before committing or pushing.
- Put long-running commands in background terminals and continue useful work until completion arrives.
