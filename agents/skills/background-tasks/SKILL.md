---
name: background-tasks
description: Run and manage session-scoped background subagents and long-lived commands. Use for delegated Finder/Librarian/Oracle/Worker work, dev servers, watchers, streaming builds, log tails, long test suites, checking task progress, collecting results, or cancelling work.
---

# Background Tasks

Use one task lifecycle for delegated agents and long-running commands. Every launch returns a task ID immediately; continue the conversation or other useful work while it runs.

## Launch

Use `start_subagent` for specialized agent work:

- `finder` — read-only workspace reconnaissance
- `librarian` — GitHub code research
- `oracle` — read-only architecture, debugging, planning, or review
- `worker` — bounded implementation and validation

Worker launches require a narrow `write_scope`. Treat it as a coordination lease until the task settles or is cancelled. Structured Worker writes are gated to the scope, and the coordinator stays read-only while the Worker runs; Worker shell effects remain policy-constrained rather than sandboxed.

Use `start_background_command` for dev servers, watchers, log tails, streaming builds, and long test suites. Use `bash` for commands that normally finish in seconds. Commands receive no stdin.

Independent launches may appear in one assistant response and run concurrently. Keep Worker scopes disjoint.

## Observe and control

- `task_list` — inventory of session tasks
- `task_status` — current progress when it unblocks immediate work
- `task_result` — collect a settled result explicitly
- `task_cancel` — request cancellation without waiting for teardown

Completion is delivered automatically when the coordinator is idle. Continue useful work after launch; polling and foreground sleep add no information. Calling `task_result` on a settled task acknowledges it and suppresses duplicate automatic delivery.

## Lifecycle

Tasks are session-scoped. Session shutdown or reload aborts subagents and terminates command process trees. A task cannot be promised to survive Pi exit.

Finder, Librarian, Oracle, and Worker receive the configured Executor MCP direct tools. Oracle's read-only behavior remains a policy constraint because Executor itself can expose mutating integrations.
