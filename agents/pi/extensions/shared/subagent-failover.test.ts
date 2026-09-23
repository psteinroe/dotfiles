import assert from "node:assert/strict";
import test from "node:test";
import { promptSubagentWithFailover } from "./subagent-failover.ts";

type Session = Parameters<typeof promptSubagentWithFailover>[0];
type Options = Parameters<typeof promptSubagentWithFailover>[2];
const models = ["openai-codex", "openai-codex-account-2", "openai-codex-account-3"]
  .map((provider) => ({ provider, id: "gpt-6-luna" })) as Options["models"];
const assistant = (stopReason: string, content: unknown[] = [], errorMessage?: string) =>
  ({ role: "assistant", stopReason, content, errorMessage });
const success = () => assistant("stop", [{ type: "text", text: "done" }]);
const failure = (error = "401 OAuth refresh failed: refresh_token_reused", content: unknown[] = []) =>
  assistant("error", content, error);

function fixture(responses: Array<unknown | (() => unknown)>) {
  const messages: unknown[] = [];
  const prompts: string[] = [];
  const switches: string[] = [];
  const thinking: string[] = [];
  const run: Options["run"] = {
    status: "running", task: "original task", turns: 0, maxTurns: undefined,
    toolCalls: [], startedAt: 0,
  };
  const session = {
    model: models[0], messages,
    async prompt(text: string) {
      prompts.push(text);
      messages.push({ role: "user", content: [{ type: "text", text }] });
      const response = responses.shift();
      const result = typeof response === "function" ? response() : response;
      if (result instanceof Error) throw result;
      messages.push(result);
      run.turns++;
    },
    async setModel(model: Options["models"][number]) {
      switches.push(model.provider);
      session.model = model;
    },
    setThinkingLevel(level: string) { thinking.push(level); },
  };
  const options: Options = { models, thinkingLevel: "medium", run };
  return { session: session as unknown as Session, messages, prompts, switches, thinking, run, options };
}

test("401 empty response switches accounts and continues the same history", async () => {
  const f = fixture([failure(), success()]);
  const completed = { role: "toolResult", toolCallId: "read-1", content: [{ type: "text", text: "file contents" }] };
  f.messages.push(completed);
  const selected: string[] = [];
  await promptSubagentWithFailover(f.session, "original task", {
    ...f.options, onModelChange: (model) => selected.push(model.provider),
  });
  assert.deepEqual(selected, [models[0].provider, models[1].provider]);
  assert.deepEqual(f.switches, [models[1].provider]);
  assert.ok(f.messages.includes(completed));
  assert.equal(f.prompts[0], "original task");
  assert.notEqual(f.prompts[1], "original task", "do not restart the original task");
  assert.match(f.prompts[1], /continu|resum/i);
  assert.deepEqual(f.thinking, ["medium", "medium"]);
  assert.equal(f.run.failoverCount, 1);
});

test("tries each account once and preserves the underlying terminal error", async () => {
  const f = fixture([failure("429 rate limit"), failure("503 service unavailable"), failure("401 unauthorized")]);
  await assert.rejects(promptSubagentWithFailover(f.session, "task", f.options), /401 unauthorized/);
  assert.equal(f.prompts.length, 3);
  assert.deepEqual(f.run.attemptedProviders, models.map((model) => model.provider));
});

test("unknown/context/request errors and successful empty answers do not rotate", async () => {
  for (const error of ["400 invalid_request_error", "context window exceeded", "permission denied reading file", "unknown fixture failure"]) {
    const f = fixture([failure(error), success()]);
    await assert.rejects(promptSubagentWithFailover(f.session, "task", f.options), new RegExp(error));
    assert.equal(f.prompts.length, 1);
  }
  const f = fixture([assistant("stop"), success()]);
  await promptSubagentWithFailover(f.session, "task", f.options);
  assert.equal(f.prompts.length, 1);
});

test("abort racing a provider failure prevents model switching", async () => {
  const controller = new AbortController();
  const f = fixture([() => { controller.abort(); return failure(); }, success()]);
  await assert.rejects(promptSubagentWithFailover(f.session, "task", { ...f.options, signal: controller.signal }), /abort/i);
  assert.deepEqual(f.switches, []);
});

test("an SDK-aborted message is terminal even without an external signal", async () => {
  const f = fixture([assistant("aborted"), success()]);
  await assert.rejects(promptSubagentWithFailover(f.session, "task", f.options), /abort/i);
  assert.equal(f.run.terminationReason, "cancelled");
  assert.deepEqual(f.switches, []);
});

test("turn limits are not reset or bypassed by failover", async () => {
  const f = fixture([failure(), success()]);
  f.run.maxTurns = 1;
  await assert.rejects(promptSubagentWithFailover(f.session, "task", f.options), /turn.limit/i);
  assert.equal(f.run.turns, 1);
  assert.equal(f.run.terminationReason, "turn_limit");
  assert.deepEqual(f.switches, []);
});

test("ambiguous interrupted tool calls fail closed rather than replay side effects", async () => {
  const f = fixture([failure("429 rate limit", [{ type: "toolCall", id: "write-1", name: "write", arguments: {} }]), success()]);
  await assert.rejects(promptSubagentWithFailover(f.session, "task", f.options), /partial|tool call|interrupted/i);
  assert.deepEqual(f.switches, []);
});

test("thrown provider failures rotate but thrown programming errors do not", async () => {
  const f = fixture([new Error("503 service unavailable"), success()]);
  await promptSubagentWithFailover(f.session, "task", f.options);
  assert.equal(f.prompts.length, 2);
  const broken = fixture([new TypeError("Cannot read properties of undefined"), success()]);
  await assert.rejects(promptSubagentWithFailover(broken.session, "task", broken.options), /Cannot read properties/);
  assert.deepEqual(broken.switches, []);
});

test("earlier assistant prose cannot mask a subsequent provider error", async () => {
  const f = fixture([failure("429 rate limit")]);
  f.messages.push(assistant("stop", [{ type: "text", text: "I will search" }]));
  await assert.rejects(promptSubagentWithFailover(f.session, "task", { ...f.options, models: [models[0]] }), /429 rate limit/);
});

test("OAuth 400 refresh failures rotate but generic 400 and forbidden 403 do not", async () => {
  for (const error of ["400 invalid_grant", "400 OAuth refresh failed: refresh_token_reused", "403 quota exceeded"]) {
    const f = fixture([failure(error), success()]);
    await promptSubagentWithFailover(f.session, "task", f.options);
    assert.equal(f.prompts.length, 2, error);
  }
  for (const error of ["400 invalid request", "403 Forbidden", "403 access denied", "403 insufficient permissions", "403 content_policy refusal"]) {
    const f = fixture([failure(error), success()]);
    await assert.rejects(promptSubagentWithFailover(f.session, "task", f.options));
    assert.deepEqual(f.switches, [], error);
  }
});

test("preflight failures before accepting the task submit the original task on the next account", async () => {
  const f = fixture([success()]);
  const prompt = f.session.prompt.bind(f.session);
  let first = true;
  f.session.prompt = async (...args) => {
    if (first) {
      first = false;
      throw new Error("No API key found for openai-codex");
    }
    await prompt(...args);
  };
  await promptSubagentWithFailover(f.session, "original task", f.options);
  assert.deepEqual(f.prompts, ["original task"]);
});

test("selection failures do not discard the task or loop on the unavailable account", async () => {
  const f = fixture([success()]);
  let calls = 0;
  f.session.setModel = async () => {
    calls++;
    if (calls === 1) throw new Error("401 unauthorized");
  };
  await promptSubagentWithFailover(f.session, "task", { ...f.options, models: models.slice(1) });
  assert.equal(calls, 2);
  assert.deepEqual(f.prompts, ["task"]);
});

test("thrown AbortError is cancellation, not an account failure", async () => {
  const error = new Error("request cancelled");
  error.name = "AbortError";
  const f = fixture([error, success()]);
  await assert.rejects(promptSubagentWithFailover(f.session, "task", f.options), /abort/i);
  assert.equal(f.run.terminationReason, "cancelled");
  assert.deepEqual(f.switches, []);
});

test("provider diagnostics redact common credential fields", async () => {
  for (const credential of ['api_key=secret-value', '"apiKey":"secret-value"', 'Authorization: Basic secret-value', 'Cookie: session=secret-value', 'refresh_token=secret-value']) {
    const f = fixture([failure(`401 unauthorized ${credential}`)]);
    await assert.rejects(promptSubagentWithFailover(f.session, "task", { ...f.options, models: [models[0]] }), (error: Error) => {
      assert.match(error.message, /401 unauthorized/);
      assert.doesNotMatch(error.message, /secret-value/);
      return true;
    });
  }
});

test("independent concurrent runs do not share attempted accounts", async () => {
  const a = fixture([failure(), success()]);
  const b = fixture([failure(), success()]);
  await Promise.all([a, b].map((f) => promptSubagentWithFailover(f.session, "task", f.options)));
  assert.deepEqual(a.run.attemptedProviders, b.run.attemptedProviders);
  assert.notStrictEqual(a.run.attemptedProviders, b.run.attemptedProviders);
});
