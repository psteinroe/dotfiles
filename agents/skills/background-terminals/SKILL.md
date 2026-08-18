---
name: background-terminals
description: Run and manage long-lived shell commands in background terminals via bg_start / bg_status / bg_list / bg_kill. Use for dev servers, watchers, streaming builds, log tails, long test suites, and any command that should keep running while work continues. Also use when a bash call has already blocked too long, when deciding between bash and a background terminal, or when the user asks what is still running.
---

# Background Terminals

Long-running commands belong in a background terminal, not in `bash`. `bash` blocks the
turn; `bg_start` returns immediately and the terminal keeps running while work continues.

## Choosing between bash and bg_start

Use `bash` when the command finishes on its own in seconds: builds you intend to wait for,
`git status`, a single test file, file operations.

Use `bg_start` when the command does not naturally end, or ends much later:

- dev servers, `vite dev`, `next dev`, API servers
- watchers, `tsc --watch`, `vitest --watch`
- log tails, `kubectl logs -f`
- long streaming builds and full test suites

Background commands get **no stdin**. Commands that prompt receive EOF, so pass credentials
and non-interactive options via env or flags.

## Start

`bg_start` takes:

- `command` — the shell command
- `title` — short recognizable label, e.g. `vite dev`. Titles show up in listings and in
  `/ps`, so make them distinct.
- `working_dir` — optional, relative to the session cwd. Defaults to the session cwd.

At most **8 terminals run concurrently**. Start independent commands with separate
`bg_start` calls in the same response; Pi executes those calls concurrently. Past the
limit, `bg_start` fails until a terminal stops. Check `bg_list` before starting a server
or watcher that may already be running.

## Do not poll

This is the main failure mode. After `bg_start`, **go do useful work.** When a terminal
exits you get a completion message automatically with a tail of its output; you do not
need to watch for it.

Only call `bg_status` when you actually need output _now_ — for example, a dev server has
to be up before you hit its URL, or you want to see how far a build has got.

Note the consumption rule: calling `bg_status` (or `bg_kill`) on a terminal that has
already finished **counts as collecting its result**, so the automatic completion message
is suppressed. You will not be told the same thing twice, and you will not miss it either.

## Inspect and stop

- `bg_status { id }` — status plus a generous tail of stdout/stderr for one terminal.
- `bg_list` — inventory of every tracked terminal with status, age, and output sizes.
  Cheap; use it to avoid duplicate servers.
- `bg_kill { ids }` — stop one or more. Sends SIGTERM, escalates to SIGKILL, and kills the
  whole process tree so child processes do not leak. Termination completes even if the
  tool call itself is aborted. Use it when a process is stuck or no longer needed.

Output retained by the extension is bounded; tool results and completion messages show a
truncated tail, labelled with how much was omitted. Redirect output in the command when
you need a complete log.

## Lifecycle and the user

Terminals are **session-scoped**: they are stopped when the session shuts down or reloads.
Do not promise the user a server that outlives the session.

Mention `/ps` when it helps the user list background terminals or stop one with
`/ps kill <id>`.
