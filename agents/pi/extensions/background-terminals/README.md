# @parke.dev/pi-background-terminals

Long-running shell commands for the [pi coding agent](https://pi.dev): dev
servers, watchers and builds that keep running while the agent works.

Four tools plus a `/ps` command:

| Tool        | What it does                                                       |
| ----------- | ------------------------------------------------------------------ |
| `bg_start`  | start a command in the background and return immediately           |
| `bg_status` | status plus a truncated tail of recent output                      |
| `bg_list`   | all terminals with status, age and output sizes                    |
| `bg_kill`   | stop one or more terminals (SIGTERM → SIGKILL, whole process tree) |

At most **8** terminals run at once. Starting a ninth fails until something is
killed. Terminals are session-scoped: everything is stopped on shutdown or
reload, so a dev server cannot outlive the session that started it.

Commands run with **Bash** on macOS and Linux, including support for guards such
as `set -euo pipefail`. Windows commands run with `ComSpec`.

Commands get **no stdin** (`stdio` stdin is ignored). Anything that prompts for
input sees EOF immediately rather than hanging — pass credentials via env or
flags instead.

When a terminal exits, its result is delivered automatically as a follow-up
message, so the agent does not need to poll. Delivery wakes an idle agent, waits
for an active turn to settle, and retries transient handoff failures. Calling
`bg_status` or `bg_kill` on an already-finished terminal **consumes** that result
and suppresses the automatic message, so the same outcome is never delivered
twice.

Output is retained in memory (bounded per stream); status and completion
messages show a truncated tail of what matters. While terminals are running,
Pi's extension-status API exposes a terse count and `/ps` hint to custom
footers such as `@parke.dev/pi-dashboard`.

The matching skill at `agents/skills/background-terminals/SKILL.md` teaches the model
when to reach for these tools instead of `bash`.

## Deployment

This source is vendored into the dotfiles and linked into Pi's global extensions by
`nix/home/agents.nix`. See `UPSTREAM.md` for provenance and local changes.

## Why not just bash

`bash` blocks the turn until the command finishes. That is correct for
`git status`, a single test file, or a build you intend to wait on.

It is wrong for anything that does not naturally end, or ends much later:

- dev servers (`vite dev`, `next dev`, an API server)
- watchers (`tsc --watch`, `vitest --watch`)
- log tails (`kubectl logs -f`)
- long streaming builds and full test suites

`bg_start` returns immediately with an id. Keep working. You will get a message
when it exits; only call `bg_status` when you need output _now_ (server up
before a request, how far a build has got). Check `bg_list` before starting a
second copy of something that may already be running.

## Diagnostics

```
/ps                 list background terminals (status, age, output sizes)
/ps kill <id>       stop one terminal
```

## License

MIT
