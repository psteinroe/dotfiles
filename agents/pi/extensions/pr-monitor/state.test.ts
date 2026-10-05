import assert from "node:assert/strict";
import test from "node:test";
import { advance, outcome, pollError, resolveTarget, targetFor, type PollState } from "./state.ts";
const head = "a".repeat(40);
const target = targetFor("https://github.com/Example/Project/pull/123", head);
const check = (conclusion: string | null = "SUCCESS", status = "COMPLETED") => ({ name: "Test", status, conclusion, detailsUrl: "https://github.com/example/project/actions/runs/1" });
const pr = (overrides = {}) => ({ headRefOid: head, state: "OPEN", isDraft: false, labels: [], mergeable: "MERGEABLE", mergeStateStatus: "CLEAN", statusCheckRollup: [check()], ...overrides });

test("target identity includes host/repo/PR/head and validates inputs", () => {
  assert.equal(target.url, "https://github.com/example/project/pull/123");
  assert.equal(resolveTarget({ url: target.url, headRefOid: head }).key, target.key);
  assert.notEqual(targetFor(target.url, "b".repeat(40)).key, target.key);
  assert.notEqual(targetFor("https://ghe.example.com/example/project/pull/123", head).key, target.key);
  for (const url of ["http://github.com/a/b/pull/1", "https://user:pass@github.com/a/b/pull/1", "https://github.com/a/b/pull/1?x=y", "https://github.com/a/b/pull/0"]) assert.throws(() => targetFor(url, head));
  assert.throws(() => targetFor(target.url, "not-a-sha"));
});
test("nonempty terminal set must stay identical for three polls", () => {
  let state: PollState | undefined;
  for (let i = 1; i <= 3; i++) {
    state = advance(target, state, pr(), i * 30_000);
    assert.equal(outcome(state, "checks"), i === 3 ? "passed" : undefined);
  }
  assert.equal(outcome(state!, "ready"), undefined);
  const ready = advance(target, state, pr({ labels: [{ name: "ready" }] }), 120_000);
  assert.equal(outcome(ready, "ready"), "ready");
});
test("delayed registration and pending checks reset the stable window", () => {
  let state = advance(target, undefined, pr(), 0);
  state = advance(target, state, pr({ statusCheckRollup: [check(null, "QUEUED")] }), 30_000);
  assert.equal(state.stablePolls, 0);
  state = advance(target, state, pr({ statusCheckRollup: [check(), { ...check(), name: "Lint" }] }), 60_000);
  assert.equal(state.stablePolls, 1);
  assert.equal(outcome(state, "checks"), undefined);
});
test("an empty, unknown, or incomplete check set cannot turn green", () => {
  for (const checks of [null, [], [check("NEW_STATE")], [{ context: "review required", state: "PENDING" }]]) {
    let state: PollState | undefined;
    for (let i = 0; i < 4; i++) state = advance(target, state, pr({ statusCheckRollup: checks }), i);
    assert.equal(state!.status, "pending");
  }
});
test("new head cannot reuse earlier success or failures", () => {
  let state: PollState | undefined;
  for (let i = 0; i < 3; i++) state = advance(target, state, pr(), i);
  const next = advance(target, state, pr({ headRefOid: "b".repeat(40), statusCheckRollup: [check("FAILURE")] }), 3);
  assert.equal(next.status, "head_changed");
  assert.equal(next.stablePolls, 0);
});
test("conflict, draft, merged, and closed are actionable terminal state", () => {
  for (const [overrides, status] of [[{ mergeable: "CONFLICTING" }, "conflict"], [{ mergeStateStatus: "DIRTY" }, "conflict"], [{ isDraft: true }, "draft"], [{ state: "MERGED" }, "merged"], [{ state: "CLOSED" }, "closed"]] as const) {
    assert.equal(advance(target, undefined, pr(overrides), 0).status, status);
  }
});
test("cancelled, timed-out and failed checks are failures; status contexts are included", () => {
  for (const conclusion of ["FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED"]) assert.equal(advance(target, undefined, pr({ statusCheckRollup: [check(conclusion)] }), 0).status, "failed");
  assert.equal(advance(target, undefined, pr({ statusCheckRollup: [{ context: "External", state: "ERROR", targetUrl: "url" }] }), 0).status, "failed");
});
test("skipped and neutral checks are terminal; ready is case-sensitive", () => {
  let state: PollState | undefined;
  for (let i = 0; i < 3; i++) state = advance(target, state, pr({ statusCheckRollup: [check("SKIPPED"), { ...check("NEUTRAL"), name: "Optional" }], labels: [{ name: "Ready" }] }), i);
  assert.equal(outcome(state!, "checks"), "passed");
  assert.equal(outcome(state!, "ready"), undefined);
});
test("malformed PR/check data is rejected instead of treated as green", () => {
  for (const overrides of [{ statusCheckRollup: {} }, { statusCheckRollup: [{}] }, { labels: [null] }, { isDraft: undefined }, { state: "UNKNOWN" }]) assert.throws(() => advance(target, undefined, pr(overrides), 0));
});
test("three consecutive errors stop the watch; successful recovery resets errors and stability", () => {
  let state: PollState | undefined;
  for (let i = 1; i <= 3; i++) {
    state = pollError(target, state, new Error("Bearer private-token ghp_private"), i);
    assert.equal(state.status, i === 3 ? "error" : "pending");
  }
  assert.ok(!state!.message!.includes("private-token"));
  assert.ok(!state!.message!.includes("ghp_private"));
  const next = advance(target, state, pr(), 4);
  assert.equal(next.errors, 0);
  assert.equal(next.stablePolls, 1);
});
