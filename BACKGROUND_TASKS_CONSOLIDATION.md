# Background Task Consolidation

## Status

Implemented on `feat/pi-background-tasks`. The task extension is the only Pi registration entrypoint for delegated agents and long-running commands. Existing subagent failover work is preserved behind adapters.

## Decision

Use one session-scoped task control plane with two launch tools:

- `start_subagent` starts Finder, Librarian, Oracle, or Worker.
- `start_background_command` starts a long-running OS command.

Both return a task handle immediately. They share `task_status`, `task_result`, `task_list`, `task_cancel`, completion delivery, UI, Herdr metadata, and shutdown semantics.

Keep execution engines separate. Child `AgentSession` lifecycle and terminal process-tree lifecycle have different setup, cancellation, output, and cleanup requirements.

## Public contract

### `start_subagent`

Input:

- `agent`: `finder | librarian | oracle | worker`
- `task`: self-contained task and completion condition
- `repos`, `owners`, `max_search_results`: Librarian scope
- `write_scope`: required Worker file or directory prefixes

The launch reserves the underlying profile capacity and returns `task-N`. Setup, prompting, provider failover, result extraction, and disposal continue asynchronously.

### `start_background_command`

Input:

- `command`
- `title`
- optional `working_dir`

The launch starts Bash on macOS/Linux or ComSpec on Windows with ignored stdin and returns `task-N`. POSIX commands run in their own process group.

### Management

- `task_status({ id })` returns current progress without consuming completion.
- `task_result({ id })` returns immediately; a settled result is acknowledged and removed from automatic delivery.
- `task_list()` returns all tracked session tasks.
- `task_cancel({ ids })` requests cancellation and returns without waiting for teardown.
- `/tasks` lists tasks; `/tasks cancel <id>` requests cancellation.

Task states are `starting`, `running`, `cancelling`, `done`, `failed`, and `cancelled`.

## Completion delivery

Settled tasks enter an idle-aware delivery queue. Delivery:

1. waits until Pi is idle and has no pending messages;
2. batches completions from the quiet window into one custom follow-up message with `triggerTurn: true`;
3. retries failed handoffs;
4. suppresses duplicates after explicit result collection or cancellation;
5. acknowledges delivered tasks so bounded history can prune them;
6. shuts down without delivering stale completions.

The coordinator should continue useful work after launch rather than polling. Progress is stored in the task registry because a tool's `onUpdate` channel is finalized when the launch tool returns.

## Subagent adapters

The existing Finder, Librarian, Oracle, and Worker implementations remain policy owners. Their top-level `index.ts` entrypoints were renamed to `adapter.ts`, so Pi no longer auto-registers the blocking tools. `tasks/index.ts` captures their definitions and runs them behind task handles.

Preserved policies:

| Profile | Model | Thinking | Local tools | Turn limit | Capacity |
| --- | --- | --- | --- | --- | --- |
| Finder | Luna | medium | read, bash | unlimited | 4 |
| Librarian | Luna | high | read, bash | 10 | 2 |
| Oracle | Sol | high | read, grep, find, ls, git_diff | 10 | 1 |
| Worker | Luna | high | read, bash, edit, write, grep, find, ls | 50 | 4 |

Provider/account failover remains inside the child session and preserves conversation/tool history.

## Executor MCP

All four profiles explicitly receive:

- `executor_execute`
- `executor_skills`
- `executor_resume`

At launch, the parent discovers the MCP adapter source path from the registered Executor tools' `sourceInfo`. Child settings clear inherited package/extension lists and use an empty resource agent directory; the loader then loads that explicit MCP path plus inline child policies. An `extensionsOverride` removes any other discovered extension before binding. The child tool allowlist omits the generic `mcp` proxy and unrelated parent tools.

A launch fails closed when any required Executor tool or a single common adapter source path is unavailable.

Oracle, Finder, and Librarian are instructed to use Executor for read-only operations. This is policy enforcement, not a hard capability boundary: `executor_execute` can reach mutating integrations. Hard enforcement requires a separately configured read-only Executor toolkit or credentials.

## Worker write ownership

Worker launches require `write_scope`. The registry and child runtime:

- canonicalize the nearest existing ancestor to catch symlink aliases;
- reject repository-wide, out-of-repository, and overlapping live scopes;
- block Worker `edit` and `write` calls outside the scope;
- block coordinator `edit` and `write` calls inside the active scope;
- block coordinator shell commands while any Worker is active;
- release ownership only when the task settles.

The scope remains a coordination lease rather than an OS sandbox: arbitrary Worker Bash commands cannot be proven safe by path inspection. Worker prompts explicitly require keeping shell writes inside the scope.

## Lifecycle

Tasks are in-memory and session-scoped.

On session shutdown or reload:

1. completion delivery closes;
2. every subagent abort controller is signalled;
3. terminal process trees receive SIGTERM and bounded SIGKILL escalation;
4. child extension shutdown hooks run;
5. child sessions dispose idempotently;
6. Herdr background metadata clears.

No task is promised to survive Pi exit or reload. Librarian workspaces remain inspectable during the session and are removed on session shutdown.

## Source layout

```text
agents/pi/extensions/
├── tasks/
│   ├── index.ts
│   ├── registry.ts
│   └── delivery.ts
├── finder/adapter.ts
├── librarian/adapter.ts
├── delegates/adapter.ts
├── background-terminals/src/
└── shared/
    ├── subagent-mcp.ts
    ├── subagent-runtime.ts
    ├── subagent-failover.ts
    ├── subagent-models.ts
    └── write-scope.ts
```

Only `tasks/index.ts` is an immediate `extensions/*/index.ts` registration entrypoint for this subsystem. The policy adapters and terminal backend are support modules.

## Resource bounds and accounting limitation

The registry retains at most 64 acknowledged settled tasks. Subagent output/details are truncated before parent storage, terminal retention is capped at 512 KiB per stream, and command status reads a bounded live tail.

Detached child usage is retained in task result details, but Pi 0.83 has no API to add usage to a parent tool result after the launch tool has already returned. Background subagent tokens and cost therefore do not contribute to the parent session footer totals. Fixing that requires an upstream delayed-usage accounting API.

## Validation

Required checks:

1. task registry unit tests;
2. idle delivery and duplicate-suppression tests;
3. registration test: six task tools, no legacy tools;
4. command start/result/cancel and process-tree cleanup tests;
5. immediate subagent launch and asynchronous failure tests;
6. exact Executor tool availability in every child profile;
7. subagent provider failover integration tests;
8. Worker scope overlap and coordinator write blocking tests;
9. Pi startup smoke test with only the task entrypoint deployed;
10. Home Manager activation/layout check and `nix flake check`.
