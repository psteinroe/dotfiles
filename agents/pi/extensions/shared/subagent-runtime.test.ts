import assert from "node:assert/strict";
import test from "node:test";
import type {
  AgentSession,
  AgentSessionEvent,
  ToolDefinition,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  bindAndPrepareChildSession,
  createActiveSubagentSessionRegistry,
  describeMissingSubagentOutput,
  extractAssistantText,
  extractLatestAssistantText,
  trackSubagentEvents,
} from "./subagent-runtime.ts";
import type { SubagentRunDetails } from "./subagent-progress.ts";

type RuntimeSession = Parameters<typeof trackSubagentEvents>[0];

type SessionFixture = RuntimeSession & {
  emit(event: AgentSessionEvent): void;
  steerCalls: string[];
  abortCalls: number;
};

function sessionFixture(): SessionFixture {
  const listeners = new Set<(event: AgentSessionEvent) => void>();
  const fixture = {
    subscribe(listener: (event: AgentSessionEvent) => void) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    async steer(prompt: string) {
      fixture.steerCalls.push(prompt);
    },
    async abort() {
      fixture.abortCalls++;
    },
    emit(event: AgentSessionEvent) {
      for (const listener of listeners) listener(event);
    },
    steerCalls: [],
    abortCalls: 0,
  } as SessionFixture;
  return fixture;
}

function runFixture(maxTurns = 3): SubagentRunDetails {
  return {
    status: "running",
    task: "fixture",
    turns: 0,
    maxTurns,
    toolCalls: [],
    startedAt: 0,
  };
}

test("prepared child sessions time out hung tool calls", async () => {
  const hungTool: ToolDefinition = {
    name: "hung_fixture",
    label: "Hung fixture",
    description: "Never resolves",
    parameters: Type.Object({}),
    async execute() {
      return new Promise(() => {});
    },
  };
  const definitions = new Map<string, ToolDefinition>([[hungTool.name, hungTool]]);
  const session = {
    async bindExtensions() {},
    getAllTools: () => [...definitions.keys()].map((name) => ({ name })),
    getToolDefinition: (name: string) => definitions.get(name),
    extensionRunner: { hasHandlers: () => false, emit: async () => undefined },
    dispose() {},
  };

  await bindAndPrepareChildSession(session as unknown as AgentSession, { toolCallTimeoutMs: 10 });
  const execute = definitions.get("hung_fixture")?.execute;
  assert.ok(execute);
  const outcome = await Promise.race([
    execute("call-1", {}, undefined, undefined, {} as any).then(
      () => "resolved",
      (error: unknown) => error instanceof Error ? error.message : String(error),
    ),
    new Promise<string>((resolve) => setTimeout(() => resolve("still running"), 50)),
  ]);

  assert.equal(outcome, 'Tool call "hung_fixture" timed out after 10 ms.');
});

test("extracts the last non-empty assistant text", () => {
  const session = {
    messages: [
      { role: "assistant", content: [{ type: "text", text: "old" }] },
      { role: "assistant", content: [{ type: "thinking", thinking: "..." }] },
      {
        role: "assistant",
        content: [
          { type: "text", text: "  final" },
          { type: "toolCall", name: "read" },
          { type: "text", text: "answer  " },
        ],
      },
    ],
  };
  assert.equal(
    extractAssistantText(session as unknown as Parameters<typeof extractAssistantText>[0]),
    "final\nanswer",
  );
});

test("does not mistake earlier assistant prose for the final response", () => {
  const session = {
    messages: [
      { role: "assistant", content: [{ type: "text", text: "I will inspect the files." }] },
      {
        role: "assistant",
        content: [
          { type: "thinking", thinking: "still working" },
          { type: "toolCall", name: "edit" },
        ],
      },
    ],
  };
  assert.equal(
    extractLatestAssistantText(
      session as unknown as Parameters<typeof extractLatestAssistantText>[0],
    ),
    "",
  );
});

test("describes turn-limit output loss separately from genuinely empty output", () => {
  const run = runFixture(50);
  run.turns = 50;
  assert.deepEqual(describeMissingSubagentOutput("worker", run), {
    terminationReason: "turn_limit",
    message:
      "Worker reached its 50-turn limit after working but did not return a final summary. Review the working-tree diff and recent tool calls.",
  });

  run.turns = 3;
  assert.deepEqual(describeMissingSubagentOutput("worker", run), {
    terminationReason: "empty_output",
    message: "Worker completed without a final text response.",
  });
});

test("forces tool updates, throttles turns, and applies the soft turn limit", async () => {
  const session = sessionFixture();
  const run = runFixture(3);
  let timestamp = 100;
  const updates: boolean[] = [];
  trackSubagentEvents(session, {
    run,
    maxTurns: run.maxTurns,
    now: () => timestamp,
    onUpdate: (force) => updates.push(force),
  });

  session.emit({
    type: "tool_execution_start",
    toolCallId: "one",
    toolName: "read",
    args: { path: "a.ts" },
  } as AgentSessionEvent);
  timestamp = 150;
  session.emit({ type: "turn_end" } as AgentSessionEvent);
  assert.equal(session.steerCalls.length, 0);
  timestamp = 219;
  session.emit({ type: "turn_end" } as AgentSessionEvent);
  await Promise.resolve();
  assert.equal(session.steerCalls.length, 1, "reserve the final turn for an answer");
  timestamp = 220;
  session.emit({ type: "turn_end" } as AgentSessionEvent);
  timestamp = 221;
  session.emit({
    type: "tool_execution_end",
    toolCallId: "one",
    isError: false,
  } as AgentSessionEvent);

  assert.deepEqual(updates, [true, false, true]);
  assert.equal(run.turns, 3);
  assert.equal(session.steerCalls.length, 1);
  assert.equal(session.abortCalls, 0);

  timestamp = 400;
  session.emit({ type: "turn_end" } as AgentSessionEvent);
  session.emit({ type: "turn_end" } as AgentSessionEvent);
  await Promise.resolve();
  assert.equal(run.turns, 5);
  assert.equal(session.abortCalls, 1);
  assert.equal((run as any).terminationReason, "turn_limit");

  const finishingSession = sessionFixture();
  const finishingRun = runFixture(3);
  trackSubagentEvents(finishingSession, { run: finishingRun, maxTurns: 3 });
  for (let turn = 1; turn < 5; turn++) {
    finishingSession.emit({ type: "turn_end" } as AgentSessionEvent);
  }
  finishingSession.emit({
    type: "turn_end",
    message: {
      role: "assistant",
      content: [{ type: "text", text: "final answer" }],
    },
  } as AgentSessionEvent);
  await Promise.resolve();
  assert.equal(finishingSession.abortCalls, 0, "do not abort a terminal text answer");
  assert.equal((finishingRun as any).terminationReason, undefined);
});

test("active session shutdown aborts and disposes late registrations once", async () => {
  let releaseAbort!: () => void;
  const abortGate = new Promise<void>((resolve) => {
    releaseAbort = resolve;
  });
  let firstAborts = 0;
  let firstDisposals = 0;
  const first = {
    abort: async () => {
      firstAborts++;
      await abortGate;
    },
    extensionRunner: { hasHandlers: () => false, emit: async () => undefined },
    dispose: () => firstDisposals++,
  };
  let lateDisposals = 0;
  const late = {
    abort: async () => undefined,
    extensionRunner: { hasHandlers: () => false, emit: async () => undefined },
    dispose: () => lateDisposals++,
  };
  const registry = createActiveSubagentSessionRegistry();
  registry.add(first);
  const shutdown = registry.shutdown();
  registry.add(late);
  releaseAbort();
  await shutdown;
  assert.equal(registry.size, 0);
  assert.equal(firstAborts, 1);
  assert.equal(firstDisposals, 1);
  assert.equal(lateDisposals, 1);
  await registry.shutdown();
  assert.equal(firstDisposals, 1);
});
