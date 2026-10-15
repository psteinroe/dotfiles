# Pi

Pi comes from `inputs.llm-agents` (`nix/home/packages.nix`). Upgrade with `nix flake update llm-agents` and `rebuild`; restart Pi afterwards, because `/reload` does not swap the binary. Both settings files pin `"tuiMode": "regular"` (Pi 1.0 defaults to fullscreen).

## MCP

Pi's built-in MCP client reads `agents/pi/mcp.json`. Foilwick uses codemode. Scryfall is temporarily disabled (`enabled: false`); its configuration is retained for re-enabling. Executor is hidden except `execute`, `skills` and `resume`. HTTP servers need a one-time sign-in:

```sh
pi mcp login executor
pi mcp login foilwick
pi mcp list
```

Subagents: Mapper gets no MCP. Oracle, Worker and Librarian load only Executor's three tools (`shared/subagent-mcp.ts`), never project MCP config or other extensions.

## Models and authentication

Main and Worker retain `claude-bridge/claude-opus-5-5` with high thinking on both platforms. Existing OpenAI-backed roles use the `openai` provider instead of `openai-codex`, with model IDs and thinking levels unchanged: Oracle uses `gpt-6-astra` with xhigh thinking, and Mapper/Finder and Librarian use `gpt-6-luna` with medium and high thinking respectively. OpenAI subagent account failover considers only `openai` and numeric `openai-account-N` aliases, never Codex accounts.

Codex credentials (`openai-codex` and `openai-codex-account-N`) have been removed from local and remote `auth.json` files. Pi automatically omits unauthenticated providers from `/model`; no hiding extension is needed. Non-Codex credentials and model defaults are unchanged.

OpenAI and OpenAI Codex have separate logins. Authenticate **OpenAI** through Pi's `/login`. `rauth pi` now copies OpenAI by default; `rauth all` still copies the full auth bundle. The legacy `rauth codex` shorthand also selects OpenAI. Copying credentials does not renew them.

After deploying these files, use `/reload` in running Pi sessions. Resumed sessions record their own model, so explicitly switch any Codex-backed sessions to the same model ID under `openai` if necessary.

## Claude usage waits

The managed Claude Bridge wrapper automatically waits on **fresh SDK subscription rejections**, not on warning text or footer percentages. Supported windows are `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet` and `seven_day_overage_included`. `allowed` and `allowed_warning` never stop a healthy turn. Successes, new tool/model turns and subsequent allowed/warning events clear old rejection metadata. Explicit SDK authentication/billing errors, credit-purchase requirements, scoped budget denials, overage caps and unknown windows do not qualify.

A fresh `rejected` five-hour event remains authoritative even when Claude's accompanying prose says “monthly spend limit.” That combination was verified to clear at the five-hour reset during the 2026-10-15 incident. Conversely, a cached five-hour warning cannot relabel a later permanent monthly billing failure.

- Pi keeps the **same pending provider request** open. No wait-model calls, model switching, new user prompts, tool execution or approval bypass happen during the wait.
- The status line shows the window, countdown, absolute UTC wake time and wake count. TUI/RPC users receive a notification; headless runs log the wait to stderr (JSON/RPC stdout stays protocol-only). `claude-usage-wait` events on Pi's extension event bus expose transitions to SDK hosts.
- Cancel normally with **Esc**, an SDK/RPC abort, or `/claude-wait-cancel`. Shutdown and session replacement also cancel. Cancelling does not queue a continuation.
- SDK `resetsAt` is interpreted strictly as Unix **seconds**, independent of local timezone. Wake-up adds 5–10 seconds of safety margin/jitter. Missing, malformed, past, wrong-unit or implausibly distant resets use bounded 1-, 2-, then 5-minute fallbacks instead of parsing localized clock text. Valid future resets are re-read after each rejection. Five-hour timestamps beyond six hours and weekly timestamps beyond eight days are considered implausible.
- Each pending request gets at most **three automatic wake-ups**, independently of Pi's short generic retry budget. Continued rejection then stops with a non-retryable diagnostic rather than starting another generic retry cycle. An unrelated ordinary transient failure still follows Pi's existing retry policy.

### Safety boundaries and persistence

Completed Pi tool results remain in the authoritative context; retry imports them into a rebuilt Claude session instead of delivering them to MCP again. Synthetic SDK rejection text is diagnostic, not partial model output. If a rejection follows **genuine partial text, thinking or tool-call content**, automatic recovery stops and preserves that response for inspection: the bridge has no safe partial-stream continuation contract, and silently replaying it could duplicate content or side effects. Send a new prompt only after reviewing the interrupted response.

Wait transitions are non-context custom entries in Pi's **session JSONL**, not cache files. The live timer belongs only to the running request. **Exit, crash, `/reload`, resume, fork or a new session never reconstruct a timer or automatically continue work from these entries.** After restarting, explicitly prompt to continue if the task is still wanted. Completed/cancelled children must not be resurrected. `--no-session` runs have no durable audit.

This covers normal Claude Bridge agent turns, including rejection after tool-result delivery. The bridge's internal compaction/branch-summary takeovers and opt-in AskClaude tool use separate SDK paths and are not automatically suspended by this wrapper; their existing cancellation/error behavior remains. Pi-managed HTTP timeouts do not time out the local sleep, but an external host's own overall task deadline can still cancel it. Separate Pi processes wait independently; there is no cross-process scheduler.

### Source integration and rollout

`extensions/claude-bridge.ts` loads the configured bridge through a small **hash-checked source overlay** (`shared/claude-bridge-source.ts`) for commit `227f5eb4450a070dfbc083a7fe75b8b35366b941`. Upstream currently discards typed reset metadata and treats retried tool results as orphans. The overlay preserves terminal rejection metadata, expires it at result/turn boundaries and enables context-based continuation. Source modules are copied into a temporary, session-isolated directory; dependencies are referenced read-only from the managed package. These temporary files contain code, not wait state. Neither the installed git checkout nor Pi's Nix-store binary is patched. A changed source hash fails closed and requires review, not a best-effort patch.

No upstream Pi change or Nix overlay is needed. The existing Home Manager extension deployment in `nix/home/agents.nix` includes these shared files. After review, deploy using the normal dotfiles workflow and restart/reload **only when idle**; do not expect existing waits or stopped turns to be adopted. Keep the bridge pin unchanged until the overlay and regression harness have been reviewed against any upgrade. Prefer replacing the overlay with upstream bridge support for typed terminal rejections and safe tool-result continuation when available.

## Account usage footer

`extensions/account-usage/` shows subscription quota for Codex and Claude Code. It is independent of model selection and does not report OpenAI API-provider usage. It refreshes every two minutes in the TUI, and `/account-usage` refreshes it immediately.

- Codex: token from Pi's own auth (`modelRegistry.getProviderAuth`).
- Claude: Claude Code's credentials (macOS Keychain, else `~/.claude/.credentials.json`, or `CLAUDE_CODE_OAUTH_TOKEN`).
- It is read-only: nothing is refreshed, written or logged.

## PR monitoring

Use `watch_pr` for automated checks (`until: "checks"`) or stable checks plus the `ready` label (`until: "ready"`). It returns a session subscription immediately after resolving the PR. Continue independent work or end the turn; updates arrive as idle-aware follow-ups. `/pr-watches` lists subscriptions; `pr_watch_status` inspects one and `pr_watch_cancel` cancels only yours.

Pi processes on the same machine share one poller for each GitHub host/repository/PR/head SHA through private snapshots and PID-owned locks in `~/.cache/pi/pr-monitor`. A new head ends the old-head watch rather than reusing its checks. Success requires a nonempty terminal check set unchanged across three samples, matching the shell waiter's stable-check window. A late subscriber waits for a fresh sample. Checks that pass while waiting for `ready` produce one interim update; pending polls stay quiet.

Subscriptions survive `/reload` in the same process, but end on Pi exit or session replacement. Other sessions remain subscribed, and a dead poller can be replaced. Existing shell watchers are not migrated or stopped. No watcher grants merge authorization or changes a PR; revalidate the head and any required label immediately before an independently authorized merge. The `iterate-pr` skill uses the shell waiter only when `watch_pr` is unavailable.

## Tests

```sh
node --test agents/pi/config.test.ts agents/pi/extensions/account-usage/*.test.ts agents/pi/extensions/pr-monitor/*.test.ts
zsh zsh/tests/rauth.test.zsh
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

Claude usage-wait unit tests use fake clocks and need no SDK runtime:

```sh
node --test agents/pi/extensions/shared/claude-usage-wait.test.ts
```

The bundled-Pi regression harness exercises the **actual patched bridge** with a test-only SDK query generator: no Claude subprocess, real model call, credentials or network. It checks fresh/stale signals, the misleading monthly-text case, tool-result import without replay, cancellation/shutdown and Pi's retry classifier. It requires the pinned bridge package already installed, but reads it without modification:

```sh
test_home=$(mktemp -d /tmp/pi-claude-usage-host.XXXXXX)
mkdir -p "$test_home/agent"
CLAUDE_BRIDGE_TEST_ENTRY="$HOME/.pi/agent/git/github.com/elidickinson/pi-claude-bridge/src/index.ts" \
HOME="$test_home" PI_CODING_AGENT_DIR="$test_home/agent" CLAUDE_BRIDGE_DEBUG=0 \
pi --no-extensions --no-tools --no-session --offline \
  -e "$PWD/agents/pi/extensions/shared/claude-usage-wait.host-test.ts" \
  --model usage-fixture/fixture -p smoke > "$test_home/output" 2>&1
rc=$?
grep CLAUDE_USAGE_WAIT_HOST_OK "$test_home/output" || rc=1
rm -rf "$test_home"
test "$rc" -eq 0
```

Success prints `CLAUDE_USAGE_WAIT_HOST_OK`. The harness has a five-second real watchdog, but all usage waits advance a fake clock; a five-hour regression test never sleeps for real minutes.
