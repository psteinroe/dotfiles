---
name: background-tasks
description: Run and manage session-scoped background subagents and long-lived commands. Use for delegated Mapper/Librarian/Oracle/Worker work, dev servers, watchers, streaming builds, log tails, long test suites, checking task progress, collecting results, or cancelling work.
---

# Background Tasks

Use one task lifecycle for delegated agents and long-running commands. Every accepted subagent launch is an ownership lease: the subagent owns its entire assigned scope until it settles.

## Launch

Use `start_subagent` for specialized agent work. Route exactly: **Mapper=where/what, Oracle=why/correctness/what should change, Worker=execution/implementation, Librarian=GitHub research.**

- `mapper` — strictly read-only WHERE/WHAT workspace mapping: locate files, symbols, config, tests, dependencies, and explicit call/data-flow anchors with file:line evidence. It must not diagnose, judge correctness, compare designs, plan, or recommend fixes.
- `librarian` — GitHub code research
- `oracle` — the default read-only analyst for WHY, correctness, root cause, architecture, planning, tradeoffs, review, and what should change
- `worker` — bounded implementation and validation

Express Mapper, Librarian, and Oracle ownership boundaries in their task text; `write_scope` is Worker-only. Worker launches require a narrow `write_scope`. Treat it as a coordination lease until the task settles or is cancelled. Structured Worker writes are gated to the scope, and the coordinator stays read-only while the Worker runs. Do not overlap Workers with unrestricted background commands; each launcher rejects the other while active. Worker shell effects remain policy-constrained rather than sandboxed.

Use `start_background_command` for dev servers, watchers, log tails, streaming builds, and long test suites. Use `bash` for commands that normally finish in seconds. Commands receive no stdin.

Before launching, partition work into bounded, non-overlapping scopes with explicit expected results. Independent launches may appear in one assistant response and run concurrently.

After launch, exclude every delegated scope from coordinator work. Continue only with clearly disjoint work; if none remains, end the turn. Reserve the final answer until every required delegated result is integrated; while required work is active, end the turn without an interim conclusion. When completion arrives, review and integrate the result before doing any remaining work in that scope.

## Observe and control

- `task_list` — inventory of session tasks
- `task_status` — current progress when it unblocks immediate work
- `task_result` — collect a settled result explicitly
- `task_cancel` — request cancellation without waiting for teardown; use it only for a user request, invalid or unsafe scope, a stuck task, or changed requirements

Completion is delivered automatically when the coordinator is idle. End the turn when no disjoint work remains; polling and foreground sleep add no information. Calling `task_result` on a settled task acknowledges it and suppresses duplicate automatic delivery. Coordinator duplication does not make a delegated task redundant and is not a cancellation reason.

## Lifecycle

Tasks are session-scoped. Session shutdown or reload aborts subagents and terminates command process trees. A task cannot be promised to survive Pi exit.

Librarian, Oracle, and Worker receive the configured Executor MCP direct tools. Mapper is deliberately limited to the local read/search tools (`read`, `grep`, `find`, `ls`) and receives no Executor MCP tools. Oracle's read-only behavior remains a policy constraint because Executor itself can expose mutating integrations.
