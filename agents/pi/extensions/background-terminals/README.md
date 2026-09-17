# Background command backend

This directory contains the process-management backend used by `extensions/tasks`.
It is not an independently loaded Pi extension.

Public tools are registered by `extensions/tasks/index.ts`:

- `start_background_command`
- `task_status`
- `task_result`
- `task_list`
- `task_cancel`

The backend preserves these invariants:

- Bash on macOS/Linux and ComSpec on Windows
- ignored stdin
- detached POSIX process groups
- bounded stdout/stderr retention
- exactly-once settlement
- SIGTERM to SIGKILL process-tree cancellation
- session-scoped cleanup

Completion delivery moved to the shared task control plane. See
`BACKGROUND_TASKS_CONSOLIDATION.md` and `agents/skills/background-tasks/SKILL.md`.

The process manager remains adapted from `@parke.dev/pi-background-terminals@0.1.0`.
See `UPSTREAM.md` and `LICENSE`.
