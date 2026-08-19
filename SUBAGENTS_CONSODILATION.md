# Subagent Consolidation Plan

## Status

Approved implementation plan. The Worker completion safeguard and 50-turn policy were implemented ahead of the structural consolidation; the directory consolidation remains pending. Preserve the public purpose of Finder, Librarian, Oracle, and Worker.

## Decision

Consolidate Finder, Librarian, Oracle, and Worker into one Pi extension at:

```text
agents/pi/extensions/subagents/
```

Keep the existing shared support directory as its sibling:

```text
agents/pi/extensions/shared/
agents/pi/extensions/subagents/
```

`subagents/index.ts` is the single Pi registration entrypoint for all four tools. `shared/` remains support code: it has no registration entrypoint and must not register a global extension. The child-only subdirectory-context extension remains nested under `shared/` and is installed explicitly into child sessions.

This structure avoids another deployment root, keeps common code reusable by the consolidated extension, and removes sibling imports among independently loaded Finder, Librarian, and Delegates extensions.

## Goals

1. Give all four tools one execution model and one tested lifecycle.
2. Express intentional differences as small, explicit specifications.
3. Keep Finder and Librarian licenses and upstream provenance auditable.
4. Preserve the fixed OpenAI model policy and current tool permissions.
5. Preserve one Oracle plus four concurrent Workers without adding a queue.
6. Improve bounded-run completion so useful work is not reported as the generic `worker returned no final answer.`
7. Preserve live progress, cancellation, parent shutdown, and deterministic child disposal.
8. Keep subdirectory context child-only while making it available consistently where useful.
9. Deploy one top-level subagent extension without duplicate tool registrations.

## Non-goals

- Do not merge the four prompts into one generic prompt.
- Do not give all four tools the same model, tools, workspace, or turn limit.
- Do not turn subdirectory context into a globally loaded extension.
- Do not restore upstream package installation or model-selection environment variables.
- Do not add a Worker queue.
- Do not change the main coordinator model.
- Do not remove or weaken cancellation, shutdown, or capacity safeguards.
- Do not discard Finder, Librarian, or subdirectory-context attribution.

## Current architecture

Pi currently loads three top-level extension entrypoints:

```text
agents/pi/extensions/finder/index.ts       -> finder
agents/pi/extensions/librarian/index.ts    -> librarian
agents/pi/extensions/delegates/index.ts    -> oracle, worker
```

They import support code from:

```text
agents/pi/extensions/shared/subagent-runtime.ts
agents/pi/extensions/shared/subagent-progress.ts
agents/pi/extensions/shared/child-session.ts
agents/pi/extensions/shared/subdir-context/
```

The current boundaries create several inconsistencies:

- Oracle and Worker share one implementation while Finder and Librarian each duplicate similar orchestration.
- Finder and Librarian return structured tool errors, while Oracle and Worker generally rethrow.
- Finder/Librarian details use `agent`; Oracle/Worker details use `delegate`.
- Bounded agents do not use one turn-budget strategy.
- Only Finder and Librarian install child-only subdirectory context.
- `delegates/progress.ts` is primarily a compatibility facade over shared progress code.
- A bounded Worker can complete substantial edits, hit its turn cutoff before emitting final text, and be reduced to `worker returned no final answer.`

## Target architecture

```text
agents/pi/extensions/
├── shared/
│   ├── child-session.ts
│   ├── child-session.test.ts
│   ├── subagent-runtime.ts
│   ├── subagent-runtime.test.ts
│   ├── subagent-progress.ts
│   ├── subagent-progress.test.ts
│   ├── subdir-context/
│   │   ├── LICENSE
│   │   ├── UPSTREAM.md
│   │   └── src/
│   │       ├── index.ts
│   │       └── index.test.ts
│   ├── THIRD_PARTY.md
│   └── LICENSE.apache-2.0
│
└── subagents/
    ├── index.ts
    ├── index.test.ts
    ├── register-subagent.ts
    ├── run-subagent.ts
    ├── contracts.ts
    ├── capacity.ts
    ├── capacity.test.ts
    ├── completion.ts
    ├── completion.test.ts
    │
    ├── finder/
    │   ├── spec.ts
    │   ├── schema.ts
    │   ├── prompt.ts
    │   ├── spec.test.ts
    │   ├── LICENSE
    │   └── UPSTREAM.md
    │
    ├── librarian/
    │   ├── spec.ts
    │   ├── schema.ts
    │   ├── prompt.ts
    │   ├── workspace.ts
    │   ├── spec.test.ts
    │   ├── LICENSE
    │   └── UPSTREAM.md
    │
    ├── oracle/
    │   ├── spec.ts
    │   ├── prompt.ts
    │   ├── git-diff.ts
    │   └── spec.test.ts
    │
    └── worker/
        ├── spec.ts
        ├── prompt.ts
        └── spec.test.ts
```

The exact file split may remain smaller when a file would contain only trivial forwarding code. Preserve the ownership boundaries even if `schema.ts` or `prompt.ts` retains an existing upstream filename.

## Autoload boundary

Pi discovers immediate extension files and `extensions/*/index.ts`. It does not independently load nested Finder, Librarian, Oracle, or Worker modules.

Only this file registers the four tools:

```text
agents/pi/extensions/subagents/index.ts
```

The following paths remain non-entrypoint implementation code:

```text
agents/pi/extensions/subagents/finder/
agents/pi/extensions/subagents/librarian/
agents/pi/extensions/subagents/oracle/
agents/pi/extensions/subagents/worker/
agents/pi/extensions/shared/
agents/pi/extensions/shared/subdir-context/
```

Add a discovery test that fails if a nested module becomes an unintended top-level extension entrypoint.

## Registration composition

The target entrypoint should have one composition responsibility:

```ts
export default function subagentsExtension(pi: ExtensionAPI) {
  const runtime = createSubagentRuntime(pi);

  runtime.register(finderSpec);
  runtime.register(librarianSpec);
  runtime.register(oracleSpec);
  runtime.register(workerSpec);
}
```

The exact API may differ, but the entrypoint must:

- register exactly `finder`, `librarian`, `oracle`, and `worker`;
- create one parent-lifecycle owner for active child sessions;
- preserve independent capacity limits per specification;
- install one `session_shutdown` handler that aborts and disposes every active child;
- avoid agent-specific execution branches in `index.ts`.

## Common specification

Represent intentional differences in typed specifications. A useful shape is:

```ts
interface SubagentSpec<Input, Metadata = Record<string, never>> {
  name: "finder" | "librarian" | "oracle" | "worker";
  label: string;
  description: string;
  promptSnippet?: string;
  promptGuidelines?: string[];
  activity: string;
  parameters: TSchema;

  provider: "openai-codex";
  model: string;
  thinking: ThinkingLevel;
  tools: readonly string[];
  maxTurns?: number;
  concurrency?: number;
  outputLimit?: number;

  normalizeInput(input: unknown): Normalized<Input>;
  taskText(input: Input): string;
  buildSystemPrompt(context: SubagentContext<Input>): string;
  buildUserPrompt(input: Input, context: SubagentContext<Input>): string;

  prepareWorkspace?(
    parent: ExtensionContext,
    input: Input,
  ): Promise<PreparedWorkspace>;
  createCustomTools?(context: SubagentContext<Input>): AgentTool[];
  childExtensions?(context: SubagentContext<Input>): ExtensionFactory[];
  metadata?(input: Input, context: SubagentContext<Input>): Metadata;
  renderCall?(input: unknown, theme: Theme): Component;
}
```

Keep hooks narrow. The specification describes policy and agent-owned setup; the common runner owns execution. Avoid a general-purpose framework that allows each specification to replace the entire lifecycle.

## Common lifecycle

Every tool invocation follows the same ordered lifecycle:

1. Normalize and validate public input.
2. Acquire the agent's capacity slot.
3. Prepare its workspace.
4. Resolve the configured OpenAI model.
5. Build an isolated resource loader.
6. Install only explicitly selected child extensions.
7. Create an in-memory child session.
8. Bind child extensions in print mode.
9. Register the active child before prompting it.
10. Bind parent cancellation to child abort.
11. Start common progress and turn tracking.
12. Prompt with template expansion disabled.
13. Capture the termination reason.
14. Extract and truncate the final assistant text.
15. Collect token and cost statistics.
16. Produce a structured success, error, or aborted result.
17. Remove listeners and active-session registration.
18. emit child `session_shutdown` and dispose exactly once.
19. Release capacity exactly once.

The runner must clean up correctly when failure occurs during workspace preparation, model lookup, resource loading, extension binding, prompting, output extraction, or parent shutdown.

## Unified result contract

All four tools should converge on one details shape:

```ts
interface SubagentDetails<
  Name extends SubagentName = SubagentName,
  Metadata = Record<string, unknown>,
> {
  agent: Name;
  status: "running" | "done" | "error" | "aborted";
  workspace: string;
  model: string;
  thinking: ThinkingLevel;
  terminationReason?:
    | "completed"
    | "cancelled"
    | "turn_limit"
    | "prompt_error"
    | "empty_output"
    | "shutdown";
  run: {
    task: string;
    turns: number;
    maxTurns?: number;
    toolCalls: SubagentToolCall[];
    startedAt: number;
    endedAt?: number;
    summaryText?: string;
    error?: string;
  };
  metadata: Metadata;
  tokens?: unknown;
  cost?: number;
  truncated?: boolean;
}
```

Use `agent` for every tool. During migration, Oracle and Worker may temporarily include the old `delegate` property if an installed renderer or stored-session compatibility test requires it. Remove the compatibility property after all consumers use `agent`.

Return structured error results rather than discarding details through a rethrow. A failed result must retain at least:

- agent name;
- workspace;
- model and thinking level;
- turn count and configured limit;
- termination reason;
- recent tool calls;
- start/end timestamps;
- useful error text.

## Agent policies

Preserve these policy differences initially:

| Agent | Model | Thinking | Workspace | Tools | Turn policy | Capacity |
|---|---|---|---|---|---|---|
| Finder | `gpt-5.6-luna` | medium | parent cwd | read, bash | unlimited | current behavior |
| Librarian | `gpt-5.6-luna` | high | isolated `/tmp/pi-librarian/run-*` | read, bash | 10 | current behavior |
| Oracle | `gpt-5.6-sol` | xhigh | parent cwd | read, grep, find, ls, `git_diff` | 10 | 1 |
| Worker | `gpt-5.6-luna` | high | parent cwd | read, bash, edit, write, grep, find, ls | 50 | 4 |

Do not broaden tool permissions during the structural move.

### Finder ownership

Finder retains:

- its upstream public query schema and description;
- upstream system/user prompt behavior;
- Luna-medium policy;
- one-shot workspace reconnaissance purpose;
- read-only behavior;
- unlimited turns unless separately reconsidered after production observation.

### Librarian ownership

Librarian retains:

- repository/owner scoping and normalization;
- isolated temporary workspace creation;
- upstream research prompt behavior;
- Luna-high policy;
- read/bash tools;
- GitHub-search result limits;
- ten-turn bounded research behavior.

### Oracle ownership

Oracle retains:

- Sol-xhigh policy;
- one-call capacity;
- read-only purpose;
- safe, argv-based `git_diff` custom tool;
- consequential reasoning/review routing guidance;
- ten-turn policy.

`git_diff` remains Oracle-owned and is not exposed through the common runtime.

### Worker ownership

Worker retains:

- Luna-high policy;
- four-call capacity;
- current editing/testing tools;
- bounded implementation purpose;
- no commit, push, PR, or product-decision authority;
- approved fifty-turn policy.

## Child resources and context

Use one isolated resource-loader baseline for all four:

- no inherited global extensions;
- no inherited skills;
- no prompt templates;
- no themes;
- no automatic context-file loading;
- explicit system prompt;
- in-memory child session;
- untrusted project resource policy unless explicitly justified otherwise.

Install the vendored subdirectory-context extension explicitly as a child extension. The desired end state is to make it available to all four agents so Oracle and Worker also discover nested repository instructions while reading files.

Treat enabling it for Oracle and Worker as a characterized behavior change, not as an incidental file move:

1. test child-only loading;
2. test root-to-leaf instruction order;
3. test that it never registers in the parent session;
4. smoke-test Oracle and Worker in a fixture with nested instructions;
5. preserve its MIT license and upstream record.

Librarian additionally installs any bounded-turn child hook required by the common turn policy.

## Turn-budget and completion design

### Existing failure mode

Before the interim completion fix, the shared tracker sent a wrap-up steer at `maxTurns` and aborted at `maxTurns + 2`. A Worker that spent all turns on tool calls could therefore:

1. perform substantial edits;
2. reach the old 30-turn limit;
3. receive a late wrap-up steer;
4. continue using tools;
5. be aborted around turn 32;
6. have no assistant message containing a non-empty text part;
7. be reported as `worker returned no final answer.`

The interim fix raises Worker to 50 turns, steers before the final reserved turn, blocks tools on the final turn, records turn-limit termination, and returns structured diagnostics. Consolidation must preserve that behavior.

That message incorrectly suggests the Worker did nothing and loses the actual termination reason.

### Target bounded-run behavior

Use one shared bounded-run policy for Librarian, Oracle, and Worker:

1. Track the remaining turn budget visibly in runtime state.
2. Before the final allowed turn, steer the child to stop exploring and summarize.
3. On the final answer turn, block further tool calls and require a text response.
4. Allow a small, explicit grace policy only if Pi's event ordering requires it.
5. Record `terminationReason: "turn_limit"` before issuing a hard abort.
6. Preserve run details when prompting resolves without final text.
7. Return a specific result such as:

   ```text
   Worker reached its 50-turn limit after applying changes but did not return a final summary. Review the working-tree diff and the recorded recent tool calls.
   ```

8. Distinguish that result from:
   - parent cancellation;
   - parent shutdown;
   - model/API failure;
   - a normally completed prompt with genuinely empty output.

Finder remains unlimited but uses the same completion extraction and structured error path.

Do not treat raising the Worker turn limit as the fix. The core problem is failure to reserve and report a final-answer phase.

## Error semantics

Adopt one convention for all four tools:

- Expected execution failures return `isError: true` with complete details.
- Parent cancellation returns `status: "aborted"` and is not mislabeled as empty output.
- Parent shutdown records `terminationReason: "shutdown"` when delivery remains possible.
- Unexpected programming errors may still throw after cleanup, but the runtime must emit a final diagnostic update first.
- Successful work followed by a missing summary reports the work as incomplete, not nonexistent.

The visible error text must name the actual reason before suggesting remediation.

## Progress behavior

Keep one shared progress implementation and one details contract. Agent specifications provide only display labels and task previews.

Every running tool should display:

- agent name;
- model and thinking level;
- workspace;
- turns and limit when bounded;
- recent tool calls;
- current activity;
- final completion, abort, or error state;
- final response preview when present.

Progress updates remain throttled for turn events and immediate for tool start/end events. No periodic elapsed-time ticker should be introduced.

## Capacity and shutdown

The consolidated runtime owns one active-session registry and per-agent capacity gates.

Required invariants:

- at most one Oracle;
- at most four Workers;
- Oracle may run alongside four Workers;
- no Worker queue;
- capacity acquisition fails immediately and clearly;
- every acquired slot is released exactly once;
- `session_shutdown` aborts and disposes all active children;
- children that finish creating during shutdown are disposed rather than orphaned;
- repeated shutdown/disposal calls remain idempotent.

Finder and Librarian retain their current effective capacity initially. Any new limits require a separate policy decision.

## Vendor provenance

Move attribution with the owned behavior:

```text
extensions/finder/LICENSE
extensions/finder/UPSTREAM.md
    -> extensions/subagents/finder/

extensions/librarian/LICENSE
extensions/librarian/UPSTREAM.md
    -> extensions/subagents/librarian/
```

Keep shared progress attribution under `extensions/shared/` because that implementation remains there.

Keep subdirectory-context attribution and MIT license together under:

```text
extensions/shared/subdir-context/
```

Update provenance text only where paths or local adaptation descriptions change. Preserve exact upstream versions and commit hashes.

Add a test or validation script that checks the expected license and `UPSTREAM.md` files after consolidation.

## Test plan

### Characterization before movement

Capture the current public contract:

- tool names and labels;
- descriptions;
- parameter schemas;
- prompt snippets and guidelines;
- `executionMode: "parallel"`;
- fixed provider/model/thinking settings;
- tool lists;
- concurrency limits;
- workspace behavior;
- prompt construction;
- output truncation;
- Oracle `git_diff` argv;
- Finder/Librarian provenance files.

### Shared runtime tests

Extend shared tests for:

- final assistant text extraction;
- thinking-only transcript;
- tool-call-only transcript;
- whitespace-only text;
- last non-empty text selection;
- cancellation before child creation;
- cancellation during prompt;
- cancellation after prompt resolution;
- wrap-up steering;
- final-turn tool blocking;
- hard-limit termination reason;
- late child registration during shutdown;
- idempotent extension shutdown/disposal;
- listener cleanup.

### Consolidated runner tests

Add tests for:

- exactly four registrations;
- no duplicate registration;
- successful final text;
- prompt failure;
- model unavailable;
- workspace preparation failure;
- child extension bind failure;
- empty final output;
- turn-limit completion without final text;
- structured error details surviving delivery;
- token/cost collection;
- output truncation;
- capacity release on every failure path;
- concurrent Oracle and Worker capacity independence.

### Agent specification tests

Finder:

- upstream schema and prompt characterization;
- Luna-medium/read/bash policy;
- unlimited-turn configuration;
- parent workspace.

Librarian:

- input normalization;
- repository/owner limits;
- temporary workspace layout;
- Luna-high/read/bash policy;
- ten-turn configuration.

Oracle:

- Sol-xhigh/read-only policy;
- safe `git_diff` targets;
- one-call capacity;
- no editing or shell tool.

Worker:

- Luna-high editing policy;
- four-call capacity;
- fifty-turn configuration;
- explicit no-commit/no-push prompt contract;
- turn-limit regression preserving diagnostic details.

### Installed-layout tests

Verify after activation:

```text
~/.pi/agent/extensions/subagents -> source subagents directory
~/.pi/agent/extensions/shared    -> source shared directory
```

Verify absence of obsolete roots:

```text
~/.pi/agent/extensions/delegates
~/.pi/agent/extensions/finder
~/.pi/agent/extensions/librarian
```

Verify nested modules are not independently discovered as extensions.

## Migration sequence

Implement in reviewable stages while deploying only states that avoid duplicate registration.

### Stage 1: Characterize

1. Add missing registration and execution tests around the existing extensions.
2. Add the Worker turn-limit/no-final-answer regression seam.
3. Record the current public registration contract.

Completion criterion: tests can detect changed registrations, policies, result details, lifecycle cleanup, and the known completion failure.

### Stage 2: Strengthen shared completion semantics

1. Add explicit termination reasons to shared tracking.
2. Add final-answer reservation/tool blocking for bounded agents.
3. Preserve structured details on empty output and turn-limit termination.
4. Keep current extension entrypoints while validating the runtime behavior.

Completion criterion: a deterministic test reproduces the old generic Worker failure and now receives a turn-limit-specific structured result.

### Stage 3: Introduce the common runner

1. Add `subagents/contracts.ts`, `register-subagent.ts`, and `run-subagent.ts`.
2. Move generic Delegate capacity/output behavior into the consolidated runtime where appropriate.
3. Keep low-level session/progress/lifecycle primitives in sibling `shared/`.
4. Do not add the active `subagents/index.ts` registration while old roots still register the same tools in a deployed session.

Completion criterion: the common runner passes lifecycle tests independently of any specific agent.

### Stage 4: Convert specifications

Convert in this order:

1. Worker
2. Oracle
3. Finder
4. Librarian

During this stage, existing top-level entrypoints may temporarily import and register the new specifications so each conversion is testable without duplicate registrations.

Completion criterion: all four existing public tools execute through the common runner and their remaining modules contain only agent-owned policy/content.

### Stage 5: Align contracts and context

1. Normalize result details on `agent`.
2. Normalize structured error behavior.
3. Remove `delegates/progress.ts` compatibility after consumers migrate.
4. Enable child-only subdirectory context for Oracle and Worker with characterization tests.
5. Replace Librarian's separate turn-budget logic with the common bounded-run policy once parity is proven.

Completion criterion: all four agents use the same lifecycle, result contract, progress path, context mechanism, and bounded completion semantics where applicable.

### Stage 6: Atomic autoload cutover

In one source/deployment transition:

1. Add `extensions/subagents/index.ts` as the single registration entrypoint.
2. Move Finder and Librarian owned files, licenses, and provenance under it.
3. Move Oracle and Worker specifications under it.
4. Delete obsolete `extensions/finder/`, `extensions/librarian/`, and `extensions/delegates/` roots.
5. Keep `extensions/shared/` as the sibling support directory.
6. Activate the Home Manager generation so the destination extension directory is recreated without stale links.

Completion criterion: Pi starts with exactly one registration each for Finder, Librarian, Oracle, and Worker, with no duplicate-tool errors and no obsolete deployed roots.

### Stage 7: Validate and deploy

Run:

1. all focused extension tests;
2. TypeScript validation against the deployed Pi version;
3. Pi startup smoke test;
4. one real Finder invocation;
5. one real Librarian invocation;
6. one real Oracle invocation;
7. one bounded Worker invocation that edits and validates a disposable fixture;
8. one Worker turn-limit fixture confirming useful diagnostics;
9. `nix flake check`;
10. local and remote installed-layout checks.

Reload only sessions that are idle and have no active child agents or background terminals.

Completion criterion: local and remote Pi sessions expose all four tools with preserved policies, clean shutdown, visible progress, and specific completion diagnostics.

## Deployment impact

`nix/home/agents.nix` already recreates `~/.pi/agent/extensions` and symlinks every immediate source entry. The final source layout therefore naturally deploys:

```text
~/.pi/agent/extensions/shared
~/.pi/agent/extensions/subagents
```

No separate internal-library deployment path is required. Confirm this behavior with an activation test rather than adding special-case deployment logic.

The TypeScript configuration already includes nested `extensions/**/*.ts`, so the target tree should not require a new include path.

## Risks and mitigations

### Duplicate registrations

Risk: old and new entrypoints load together.

Mitigation: activate `subagents/index.ts` only in the same final transition that removes the old three roots.

### One extension becomes a larger failure domain

Risk: an import error in one specification prevents the consolidated extension from loading.

Mitigation: keep imports simple, add a registration smoke test, typecheck the full tree, and keep agent-specific startup work lazy inside execution rather than module initialization.

### Behavioral drift hidden by abstraction

Risk: a generic runner accidentally broadens tools, changes workspaces, or alters prompts.

Mitigation: characterize each specification and keep permissions/prompt/workspace decisions out of the runner.

### Lost attribution

Risk: moving vendored files separates them from licenses or provenance.

Mitigation: move owned notices atomically and validate exact upstream commit records.

### Turn-limit regressions

Risk: final-answer enforcement blocks legitimate final validation or aborts too early.

Mitigation: use deterministic event-order tests and a real bounded Worker fixture before deployment.

### Subdirectory-context leakage

Risk: nested context support loads into the parent or unrelated extensions.

Mitigation: retain `noExtensions: true`, install it only through child `extensionFactories`, and test the parent tool list/handlers.

### Lost child diagnostics

Risk: in-memory sessions disappear before the coordinator can understand a failure.

Mitigation: copy termination reason, turns, recent tools, workspace, and summary/error text into the parent tool result before child disposal. Consider opt-in redacted transcript persistence only if structured diagnostics remain insufficient.

## Acceptance criteria

The consolidation is complete when all of the following are true:

- `extensions/subagents/index.ts` is the only registration entrypoint for the four tools.
- `extensions/shared/` remains its sibling and contains no global extension registration.
- Pi registers exactly `finder`, `librarian`, `oracle`, and `worker` once each.
- All four execute through the same runner and result contract.
- Models, thinking levels, tools, workspaces, prompts, turn limits, and capacities match their approved policies.
- Oracle remains read-only and solely owns `git_diff`.
- Worker retains editing/testing capability and no commit/push authority.
- Finder and Librarian retain exact upstream provenance and licenses.
- Subdirectory context remains child-only.
- Parent cancellation and shutdown dispose every child exactly once.
- One Oracle can run alongside four Workers.
- A turn-limited Worker reports `turn_limit` with useful details rather than `worker returned no final answer.`
- Focused tests, Pi type validation, startup smoke tests, real tool smokes, and `nix flake check` pass.
- Home Manager activation removes obsolete deployed extension roots.
- Safe reload skips active sessions and successfully reloads idle child-free sessions.
