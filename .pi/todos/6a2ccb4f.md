{
  "id": "6a2ccb4f",
  "title": "Build Pi sleep-check extension",
  "tags": [
    "pi",
    "extension",
    "sleep-check"
  ],
  "status": "open",
  "created_at": "2026-05-07T12:29:29.857Z"
}

## Goal
Create a Pi extension that warns when it is too late and asks whether to keep using Pi.

## Target path
`~/.pi/agent/extensions/sleep-check.ts`

## Requirements
- Warn when current local time is inside configured sleep window.
- Default sleep window: `23:30` through `06:00`.
- Configurable via env vars:
  - `PI_BEDTIME`
  - `PI_SLEEP_WARNING_UNTIL`
- Strict confirmation is desired by default:
  - Ask: “Are you sure you want to keep using Pi?”
  - If yes, continue.
  - If no/cancel/timeout, notify user and call `ctx.shutdown()`.
- Avoid notification/confirmation spam with a cooldown.
- Add `/sleep-check` command to manually report current status.

## Notes
Use Pi extension APIs from docs:
- `pi.on("session_start", ...)`
- `pi.on("input", ...)`
- `ctx.ui.notify(...)`
- `ctx.ui.confirm(...)`
- `ctx.shutdown()`
- `pi.registerCommand("sleep-check", ...)`

## Acceptance criteria
- Extension loads via auto-discovery.
- `/sleep-check` works.
- Sleep window handles crossing midnight.
- Strict confirmation appears when too late.
- Declining or timing out exits Pi gracefully.
