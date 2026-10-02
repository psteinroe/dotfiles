import assert from "node:assert/strict";
import test from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { createUsageExtension, type UsageDependencies } from "./index.ts";

const tick = () => new Promise<void>((resolve) => setImmediate(resolve));
function harness(overrides: Partial<UsageDependencies> = {}, mode = "tui") {
  const events = new Map<string, Function>();
  let command: any;
  const statuses: (string | undefined)[] = [];
  let credentials = 0, requests = 0;
  const ctx = { mode, ui: { setStatus: (_key: string, value?: string) => statuses.push(value), notify() {} } } as unknown as ExtensionContext;
  const pi = { on: (name: string, handler: Function) => events.set(name, handler), registerCommand: (_name: string, entry: any) => { command = entry; } } as unknown as ExtensionAPI;
  createUsageExtension({ credential: async () => { credentials++; return { access: "fixture" }; },
    fetch: (async () => { requests++; return new Response(JSON.stringify({ five_hour: { utilization: 17 }, rate_limit: { primary_window: { used_percent: 24, limit_window_seconds: 18000 } } })); }) as typeof fetch,
    ...overrides })(pi);
  return { statuses, ctx, emit: (name: string) => events.get(name)?.({}, ctx), refresh: () => command.handler("", ctx),
    counts: () => ({ credentials, requests }) };
}
test("factory has no resources, TUI shows both accounts, normal events obey TTL", async () => {
  let now = 0;
  const h = harness({ now: () => now });
  assert.deepEqual(h.counts(), { credentials: 0, requests: 0 });
  h.emit("session_start"); await tick();
  assert.match(h.statuses.at(-1)!, /Codex 5h 76% left \| Claude 5h 83% left/);
  h.emit("agent_end"); h.emit("model_select"); await tick();
  assert.equal(h.counts().requests, 2);
  now = 120000;
  h.emit("agent_end"); await tick();
  assert.equal(h.counts().requests, 4);
  await h.refresh();
  assert.equal(h.counts().requests, 6);
  h.emit("session_shutdown"); h.emit("session_shutdown");
  assert.equal(h.statuses.at(-1), undefined);
});
test("print/JSON/RPC modes never read credentials, poll or fetch", async () => {
  for (const mode of ["print", "json", "rpc"]) {
    const h = harness({}, mode);
    h.emit("session_start"); h.emit("agent_end"); await h.refresh(); await tick();
    assert.deepEqual(h.counts(), { credentials: 0, requests: 0 });
    assert.deepEqual(h.statuses, []);
    h.emit("session_shutdown");
  }
});
test("concurrent events deduplicate and shutdown aborts work without repaint", async () => {
  let signal: AbortSignal | undefined;
  let calls = 0;
  const h = harness({ credential: async (_provider, _ctx, active) => { signal = active; calls++; return new Promise(() => {}); } });
  h.emit("session_start"); h.emit("agent_end"); h.emit("model_select");
  const pending = h.refresh();
  assert.equal(calls, 2);
  h.emit("session_shutdown");
  assert.equal(signal?.aborted, true);
  const count = h.statuses.length;
  await pending; await tick();
  assert.equal(h.statuses.length, count);
  assert.equal(h.statuses.at(-1), undefined);
});
test("deadline bounds even an uncooperative credential resolver", async () => {
  const h = harness({ timeoutMs: 10, credential: async () => new Promise(() => {}) });
  h.emit("session_start");
  const pending = h.refresh();
  await delay(20); await pending;
  assert.equal(h.statuses.at(-1), "Codex unavailable | Claude unavailable");
  h.emit("session_shutdown");
});
test("session replacement invalidates old work and starts only one new owner", async () => {
  let resolveOld: (value: any) => void = () => {};
  let reads = 0;
  const h = harness({ credential: async () => {
    reads++;
    if (reads <= 2) return new Promise((resolve) => { resolveOld = resolve; });
    return { access: "fixture" };
  } });
  h.emit("session_start"); h.emit("session_start"); await tick();
  const count = h.statuses.length;
  resolveOld({ access: "private-old-token" }); await tick();
  assert.equal(h.statuses.length, count);
  assert.equal(h.counts().requests, 2);
  h.emit("session_shutdown");
});
test("temporary failure keeps known windows, marked stale once old", async () => {
  let now = 0, fail = false;
  const h = harness({ now: () => now, fetch: (async () => {
    if (fail) throw new Error("private-token private-email");
    return new Response(JSON.stringify({ five_hour: { utilization: 17 }, rate_limit: { primary_window: { used_percent: 24, limit_window_seconds: 18000 } } }));
  }) as typeof fetch });
  h.emit("session_start"); await tick();
  fail = true; now = 120000;
  await h.refresh();
  assert.match(h.statuses.at(-1)!, /Codex 5h 76% left \| Claude 5h 83% left$/);
  now = 300001;
  await h.refresh();
  assert.match(h.statuses.at(-1)!, /Codex .*\(stale\).*Claude .*\(stale\)/);
  assert.doesNotMatch(h.statuses.at(-1)!, /private-/);
  h.emit("session_shutdown");
});
