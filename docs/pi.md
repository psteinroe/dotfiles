# Pi

Pi comes from `inputs.llm-agents` (`nix/home/packages.nix`). Upgrade with `nix flake update llm-agents` and `rebuild`; restart Pi afterwards, because `/reload` does not swap the binary. Both settings files pin `"tuiMode": "regular"` (Pi 1.0 defaults to fullscreen).

## MCP

Pi's built-in MCP client reads `agents/pi/mcp.json`. Foilwick and Scryfall use codemode. Executor is hidden except `execute`, `skills` and `resume`. HTTP servers need a one-time sign-in:

```sh
pi mcp login executor
pi mcp login foilwick
pi mcp list
```

Subagents: Mapper gets no MCP. Oracle, Worker and Librarian load only Executor's three tools (`shared/subagent-mcp.ts`), never project MCP config or other extensions.

## Account usage footer

`extensions/account-usage/` shows the remaining subscription quota for the single Codex and Claude Code accounts, e.g. `Codex 5h 76% left ↻1h | Claude 5h 83% left`. It refreshes every two minutes in the TUI, and `/account-usage` refreshes it immediately. It replaces `pi-multi-account`, which only provided this footer here.

- Codex: token from Pi's own auth (`modelRegistry.getProviderAuth`).
- Claude: Claude Code's credentials (macOS Keychain, else `~/.claude/.credentials.json`, or `CLAUDE_CODE_OAUTH_TOKEN`).
- It is read-only: nothing is refreshed, written or logged. "sign in" means log in normally (`/login` for Codex, `claude` for Claude Code).

## PR monitoring

Use `watch_pr` for automated checks (`until: "checks"`) or stable checks plus the `ready` label (`until: "ready"`). It returns a session subscription immediately after resolving the PR. Continue independent work or end the turn; updates arrive as idle-aware follow-ups. `/pr-watches` lists subscriptions; `pr_watch_status` inspects one and `pr_watch_cancel` cancels only yours.

Pi processes on the same machine share one poller for each GitHub host/repository/PR/head SHA through private snapshots and PID-owned locks in `~/.cache/pi/pr-monitor`. A new head ends the old-head watch rather than reusing its checks. Success requires a nonempty terminal check set unchanged across three samples, matching the shell waiter's stable-check window. A late subscriber waits for a fresh sample. Checks that pass while waiting for `ready` produce one interim update; pending polls stay quiet.

Subscriptions survive `/reload` in the same process, but end on Pi exit or session replacement. Other sessions remain subscribed, and a dead poller can be replaced. Existing shell watchers are not migrated or stopped. No watcher grants merge authorization or changes a PR; revalidate the head and any required label immediately before an independently authorized merge. The `iterate-pr` skill uses the shell waiter only when `watch_pr` is unavailable.

## Tests

```sh
node --test agents/pi/config.test.ts agents/pi/extensions/account-usage/*.test.ts agents/pi/extensions/pr-monitor/*.test.ts
bash agents/skills/iterate-pr/scripts/wait-for-pr-checks.test.sh
```

For the PR monitor adapter smoke test in bundled Pi 1.0 (synthetic provider and local mock `gh`, no network or real credentials):

```sh
test_home=$(mktemp -d /tmp/pi-pr-monitor-host.XXXXXX)
mkdir -p "$test_home/agent"
HOME="$test_home" PI_CODING_AGENT_DIR="$test_home/agent" pi \
  --no-extensions --no-tools --no-session --offline \
  -e "$PWD/agents/pi/extensions/pr-monitor/host-test.ts" \
  --model openai-codex/pr-monitor-fixture -p smoke
rm -rf "$test_home"
```

Success prints `PR_MONITOR_HOST_OK`. The PR monitor core tests use Node's TypeScript stripping and need no Pi SDK dependency.

The subagent tests under `extensions/shared`, `delegates`, `finder`, `librarian` and `tasks` additionally need the Pi 1.0 SDK (`@earendil-works/pi-coding-agent`) resolvable from Node.
