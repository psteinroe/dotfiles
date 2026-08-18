import assert from "node:assert/strict";
import test from "node:test";
import type { AgentSessionEvent } from "@earendil-works/pi-coding-agent";
import {
  createActiveSubagentSessionRegistry,
  extractAssistantText,
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
  timestamp = 219;
  session.emit({ type: "turn_end" } as AgentSessionEvent);
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
