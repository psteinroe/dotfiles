import assert from "node:assert/strict";
import test from "node:test";
import { planClaudeUsageWait, retryClaudeUsage } from "./claude-usage-wait.ts";

const now = Date.parse("2026-10-15T12:20:00Z");
const cap = (resetsAt: unknown = (now + 5 * 3600_000) / 1000) => ({
  status: "rejected", rateLimitType: "five_hour", resetsAt,
});
const failure = (info: unknown = cap(), content: any[] = []) => ({
  type: "error", reason: "error", error: {
    role: "assistant", stopReason: "error", content,
    errorMessage: "Claude rate limit (five_hour): You've hit your monthly spend limit",
    claudeUsageLimit: info,
  },
});
const success = { type: "done", reason: "stop", message: { content: [], stopReason: "stop" } };
async function* events(...values: any[]) { yield* values; }
async function collect<T>(values: AsyncIterable<T>): Promise<T[]> {
  const result: T[] = [];
  for await (const value of values) result.push(value);
  return result;
}
function fixture(responses: any[][]) {
  let time = now;
  const calls: boolean[] = [];
  const updates: any[] = [];
  const sleeps: number[] = [];
  const controller = new AbortController();
  const deps = {
    now: () => time, random: () => 0,
    sleep: async (ms: number, signal: AbortSignal) => {
      signal.throwIfAborted(); sleeps.push(ms); time += ms;
    },
    update: (state: any) => updates.push(state),
  };
  return {
    calls, updates, sleeps, controller, deps,
    run: () => collect(retryClaudeUsage((retry) => {
      calls.push(retry);
      return events(...(responses.shift() ?? [failure()]));
    }, controller.signal, deps)),
    time: () => time,
  };
}

test("five-hour structured reset wins over monthly billing text and generic retry budget", async () => {
  const f = fixture([[failure()], [success]]);
  const result = await f.run();
  assert.deepEqual(result, [success]);
  assert.deepEqual(f.calls, [false, true]);
  assert.equal(f.time(), now + 5 * 3600_000 + 5000);
  assert.ok(f.sleeps.every((ms) => ms > 0 && ms <= 15_000));
  assert.equal(f.updates[0].phase, "waiting");
  assert.equal(f.updates.at(-1).phase, "finished");
});

test("SDK timestamps are seconds, never local time or heuristically milliseconds", () => {
  assert.equal(planClaudeUsageWait(cap(), now, 0, 0)?.wakeAt, now + 5 * 3600_000 + 5000);
  for (const bad of [undefined, null, NaN, Infinity, -1, "5:20pm (UTC)", now + 3600_000, now / 1000 - 10]) {
    assert.equal(planClaudeUsageWait({ ...cap(), resetsAt: bad }, now, 0, 0)?.wakeAt, now + 60_000 + 5000);
  }
});

test("only explicit resettable subscription rejections qualify", () => {
  for (const info of [null, {}, { ...cap(), status: "allowed_warning" }, { ...cap(), rateLimitType: "overage" },
    { ...cap(), rateLimitType: "monthly" }, { ...cap(), errorCode: "credits_required" }, { ...cap(), limitScope: "group_pool" }]) {
    assert.equal(planClaudeUsageWait(info, now, 0, 0), undefined);
  }
});

test("missing, malformed and stale resets use bounded 1/2/5-minute fallback, then stop", async () => {
  const f = fixture(Array.from({ length: 4 }, () => [failure(cap("invalid"))]));
  const result = await f.run();
  assert.equal(f.calls.length, 4);
  assert.equal(f.time() - now, (60 + 120 + 300 + 15) * 1000);
  assert.ok(result[0].type === "error");
  assert.match(result[0].error.errorMessage!, /stopped after 3/);
  assert.doesNotMatch(result[0].error.errorMessage!, /rate.?limit|429|overloaded/i);
});

test("updated resets are read on each rejection, duplicate events do not schedule more requests", async () => {
  const f = fixture([
    [failure(cap((now + 60_000) / 1000))],
    [failure(cap((now + 3600_000) / 1000))], [success],
  ]);
  await f.run();
  assert.deepEqual(f.calls, [false, true, true]);
  assert.equal(f.time(), now + 3600_000 + 5000);
});

test("cancellation during a long wait never starts another request", async () => {
  const f = fixture([[failure()], [success]]);
  f.deps.sleep = async (_ms, signal) => {
    f.controller.abort(); signal.throwIfAborted();
  };
  const result = await f.run();
  assert.ok(result[0].type === "error");
  assert.equal(result[0].reason, "aborted");
  assert.deepEqual(f.calls, [false]);
  assert.equal(f.updates.at(-1).phase, "cancelled");
});

test("pre-aborted or shutdown requests are never dispatched", async () => {
  const f = fixture([[success]]);
  f.controller.abort();
  const result = await f.run();
  assert.deepEqual(f.calls, []);
  assert.ok(result[0].type === "error");
  assert.equal(result[0].reason, "aborted");
});

test("ordinary errors and successful tool results pass through unchanged", async () => {
  for (const errorMessage of ["401 authentication failed", "monthly spend limit", "429 rate limit", "network failed"]) {
    const event = failure(undefined);
    delete event.error.claudeUsageLimit;
    event.error.errorMessage = errorMessage;
    const f = fixture([[event]]);
    assert.deepEqual(await f.run(), [event]);
    assert.equal(f.calls.length, 1);
    assert.deepEqual(f.sleeps, []);
  }
  const done = { ...success, reason: "toolUse", message: { content: [{ type: "toolCall", id: "one" }] } };
  const f = fixture([[done]]);
  assert.deepEqual(await f.run(), [done]);
});

test("partial streaming text/thinking/tool calls are preserved and never replayed", async () => {
  for (const block of [{ type: "text", text: "partial" }, { type: "thinking", thinking: "partial" }, { type: "toolCall", id: "side-effect" }]) {
    const delta = { type: "text_delta", delta: "partial", partial: { content: [block] } };
    const event = failure(cap(), [block]);
    const f = fixture([[delta, event], [success]]);
    const result = await f.run();
    assert.strictEqual(result[0], delta);
    assert.ok(result[1].type === "error");
    assert.deepEqual(result[1].error.content, [block]);
    assert.match(result[1].error.errorMessage!, /contains content/);
    assert.equal(f.calls.length, 1);
    assert.deepEqual(f.sleeps, []);
  }
});

test("empty starts are hidden while waiting and successful stream start is emitted once", async () => {
  const start = { type: "start", partial: { content: [] } };
  const f = fixture([[start, failure()], [start, success]]);
  assert.deepEqual(await f.run(), [start, success]);
});

test("absolute SDK reset is independent of timezone and DST; weekly windows are supported", () => {
  const previous = process.env.TZ;
  try {
    for (const zone of ["UTC", "America/New_York", "Europe/Berlin", "Asia/Kolkata"]) {
      process.env.TZ = zone;
      assert.equal(new Date(planClaudeUsageWait(cap(), now, 0, 0)!.wakeAt).toISOString(), "2026-10-15T17:20:05.000Z");
    }
    const week = { ...cap((now + 7 * 24 * 3600_000) / 1000), rateLimitType: "seven_day" };
    assert.equal(planClaudeUsageWait(week, now, 0, 1)?.wakeAt, now + 7 * 24 * 3600_000 + 10_000);
    assert.equal(planClaudeUsageWait(cap((now + 7 * 3600_000) / 1000), now, 0, 0)?.fallback, true);
  } finally {
    if (previous === undefined) delete process.env.TZ;
    else process.env.TZ = previous;
  }
});

test("abort racing the exact wake deadline wins over automatic resumption", async () => {
  const f = fixture([[failure(cap((now + 1000) / 1000))], [success]]);
  const sleep = f.deps.sleep;
  f.deps.sleep = async (ms, signal) => { await sleep(ms, signal); f.controller.abort(); };
  const result = await f.run();
  assert.ok(result[0].type === "error");
  assert.equal(result[0].reason, "aborted");
  assert.deepEqual(f.calls, [false]);
});

test("cancellation during terminal cleanup emits exactly one terminal event", async () => {
  const controller = new AbortController();
  const result = await collect(retryClaudeUsage(() => (async function* () {
    yield success as any;
    controller.abort();
  })(), controller.signal));
  assert.equal(result.length, 1);
  assert.ok(result[0].type === "error");
  assert.equal(result[0].reason, "aborted");
});
