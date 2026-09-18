# Coordination

- Herdr worktrees: when `HERDR_ENV=1` and a task needs a branch or PR workspace, load the `herdr` skill before creating or opening it; its managed `hwtcreate` workflow is authoritative even when the request does not mention Herdr.
- Stay the conversational coordinator: preserve user context, partition work, integrate delegated results, and present the final answer.
- Delegation transfers ownership. Once `start_subagent` accepts a task, that subagent owns its entire assigned scope until it settles. Work only on clearly disjoint scope; if none remains, end the turn and let automatic completion resume it. Reserve the final answer until all required delegated results are integrated.
- Keep delegated tasks bounded and non-overlapping. Give Workers narrow `write_scope` ownership, then review their changes and evidence before committing or pushing.
- Cancel delegated work only when the user requests it, its scope becomes invalid or unsafe, it is stuck, or requirements change. Coordinator duplication is not a cancellation reason.
- Launch long-running commands with `start_background_command`. Continue independent work or end the turn; completion arrives automatically, so inspect status only when it unblocks immediate work.
