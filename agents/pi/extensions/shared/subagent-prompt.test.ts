import assert from "node:assert/strict";
import test from "node:test";
import { promptSubagent } from "./subagent-prompt.ts";

function fixture() {
  const model = { provider: "openai", id: "fixture" } as any;
  const run = { turns: 0, maxTurns: 5 } as any;
  const calls: string[] = [];
  const session = {
    model,
    messages: [] as any[],
    async setModel(next: any) { calls.push("setModel"); session.model = next; },
    setThinkingLevel() {},
    async prompt(text: string) { calls.push(text); },
  };
  return { model, run, calls, session, options: { models: [model], thinkingLevel: "high" as const, run } };
}

test("submits the original task once without changing providers", async () => {
  const f = fixture();
  await promptSubagent(f.session as any, "original task", f.options);
  assert.deepEqual(f.calls, ["original task"]);
});

test("rejects multiple account candidates before any model call", async () => {
  const f = fixture();
  f.options.models.push({ provider: "openai-account-1", id: "fixture" } as any);
  await assert.rejects(promptSubagent(f.session as any, "task", f.options), /exactly one/);
  assert.deepEqual(f.calls, []);
});

test("a failed response is terminal and redacts provider credentials", async () => {
  const f = fixture();
  f.session.prompt = async (text: string) => {
    f.calls.push(text);
    f.session.messages.push({ role: "assistant", stopReason: "error", errorMessage: "401 Bearer synthetic-secret" });
  };
  await assert.rejects(promptSubagent(f.session as any, "task", f.options), (error: Error) => {
    assert.match(error.message, /401/);
    assert.doesNotMatch(error.message, /synthetic-secret/);
    return true;
  });
  assert.deepEqual(f.calls, ["task"]);
});

test("pre-aborted work never prompts a model", async () => {
  const f = fixture();
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(promptSubagent(f.session as any, "task", { ...f.options, signal: controller.signal }), { name: "AbortError" });
  assert.equal(f.run.terminationReason, "cancelled");
  assert.deepEqual(f.calls, []);
});

test("accepts a successful final answer on the last permitted turn", async () => {
  const f = fixture();
  f.session.prompt = async () => {
    f.run.turns = 5;
    f.session.messages.push({ role: "assistant", stopReason: "stop", content: [{ type: "text", text: "done" }] });
  };
  await promptSubagent(f.session as any, "task", f.options);
  assert.equal(f.run.terminationReason, undefined);
});

test("turn-budget termination is not converted to a provider error", async () => {
  const f = fixture();
  f.run.turns = 5;
  await assert.rejects(promptSubagent(f.session as any, "task", f.options), /turn limit/);
  assert.equal(f.run.terminationReason, "turn_limit");
  assert.deepEqual(f.calls, []);
});
