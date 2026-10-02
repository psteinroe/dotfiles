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

## Tests

```sh
node --test agents/pi/config.test.ts agents/pi/extensions/account-usage/*.test.ts
```

The subagent tests under `extensions/shared`, `delegates`, `finder`, `librarian` and `tasks` additionally need the Pi 1.0 SDK (`@earendil-works/pi-coding-agent`) resolvable from Node.
