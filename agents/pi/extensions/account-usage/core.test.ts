import assert from "node:assert/strict";
import test from "node:test";
import { abortable, fetchUsage, formatUsage, parseUsage, USAGE_URLS } from "./core.ts";

const now = Date.parse("2026-01-01T00:00:00Z");
test("parses actual windows and explicitly reports remaining quota/reset", () => {
  const windows = parseUsage("openai-codex", { rate_limit: {
    primary_window: { used_percent: 24, limit_window_seconds: 18000, reset_at: (now + 3600000) / 1000 },
    secondary_window: { used_percent: 46, limit_window_seconds: 604800 },
  } });
  assert.equal(formatUsage("Codex", { windows, fetchedAt: now }, now), "Codex 5h 76% left ↻1h · 7d 54% left");
  assert.deepEqual(parseUsage("claude-bridge", { five_hour: { utilization: 17, resets_at: "2026-01-01T00:30:00Z" }, seven_day: { utilization: 110 } }),
    [{ label: "5h", used: 17, resetsAt: now + 1800000 }, { label: "7d", used: 110, resetsAt: undefined }]);
});
test("does not invent missing or malformed windows", () => {
  for (const body of [null, {}, { five_hour: { utilization: "12" } }, { five_hour: { utilization: -1 } }, { five_hour: { utilization: NaN } }]) {
    assert.deepEqual(parseUsage("claude-bridge", body), []);
  }
  assert.deepEqual(parseUsage("openai-codex", { rate_limit: { primary_window: { used_percent: 1 } } }), []);
  assert.equal(formatUsage("Claude", { reason: "unavailable" }), "Claude unavailable");
  assert.match(formatUsage("Claude", { windows: [{ label: "5h", used: 110 }], fetchedAt: now }, now + 300001), /0% left \(stale\)/);
});
test("requests only fixed endpoints without redirects, with correct auth headers", async () => {
  for (const provider of ["openai-codex", "claude-bridge"] as const) {
    const fakeFetch = (async (url, options) => {
      assert.equal(url, USAGE_URLS[provider]);
      assert.equal(options?.redirect, "error");
      assert.equal(options?.method, "GET");
      const headers = options?.headers as Record<string, string>;
      assert.equal(headers.Authorization, "Bearer fixture-secret");
      if (provider === "openai-codex") assert.equal(headers["ChatGPT-Account-Id"], "fixture-account");
      else assert.equal(headers["anthropic-beta"], "oauth-2025-04-20");
      return new Response(JSON.stringify(provider === "claude-bridge" ? { five_hour: { utilization: 1 } } : { rate_limit: { primary_window: { used_percent: 2, limit_window_seconds: 18000 } } }));
    }) as typeof fetch;
    const state = await fetchUsage(provider, { access: "fixture-secret", accountId: "fixture-account" }, new AbortController().signal, fakeFetch, () => now);
    assert.ok("windows" in state);
  }
});
test("never renders remote error bodies, thrown errors, or injected headers", async () => {
  const signal = new AbortController().signal;
  const failure = await fetchUsage("claude-bridge", { access: "fixture-secret" }, signal,
    (async () => { throw new Error("fixture-secret private@example.test"); }) as typeof fetch);
  assert.deepEqual(failure, { reason: "unavailable" });
  const denied = await fetchUsage("claude-bridge", { access: "fixture-secret" }, signal,
    (async () => new Response("fixture-secret", { status: 401 })) as typeof fetch);
  assert.deepEqual(denied, { reason: "sign in" });
  let requests = 0;
  const forbidden = (async () => { requests++; throw new Error(); }) as typeof fetch;
  await fetchUsage("openai-codex", { access: "token\nheader" }, signal, forbidden);
  await fetchUsage("openai-codex", { access: "token", accountId: "id\nheader" }, signal, forbidden);
  assert.equal(requests, 0);
});
test("abort bounds uncooperative credential, fetch and response-body promises", async () => {
  const controller = new AbortController();
  const pending = abortable(new Promise<void>(() => {}), controller.signal);
  controller.abort();
  await assert.rejects(pending, /cancelled/);
  const bodyAbort = new AbortController();
  const body = fetchUsage("claude-bridge", { access: "fixture" }, bodyAbort.signal,
    (async () => ({ ok: true, json: () => new Promise(() => {}) })) as any);
  await new Promise<void>((resolve) => setImmediate(resolve));
  bodyAbort.abort();
  assert.deepEqual(await body, { reason: "unavailable" });
});
