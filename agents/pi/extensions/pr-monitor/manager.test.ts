import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import test from "node:test";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { PrMonitor, type WatchSnapshot } from "./manager.ts";
import { targetFor } from "./state.ts";
import { SharedStore } from "./store.ts";
const target = targetFor("https://github.com/example/project/pull/123", "a".repeat(40));
const pr = (overrides = {}) => ({ headRefOid: target.head, state: "OPEN", isDraft: false, labels: [], mergeable: "MERGEABLE", mergeStateStatus: "CLEAN", statusCheckRollup: [{ name: "Test", status: "COMPLETED", conclusion: "SUCCESS" }], ...overrides });
function fixture(t: test.TestContext) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pr-monitor-test-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return new SharedStore(dir);
}

test("two independent managers share polling; one session deduplicates subscriptions", async t => {
  const store = fixture(t);
  let now = 0, polls = 0;
  const notifications: WatchSnapshot[] = [];
  const options = { now: () => now, intervalMs: 30_000, poll: async () => { polls++; return pr(); }, notify: (w: WatchSnapshot) => notifications.push(w) };
  const a = new PrMonitor(store, options), b = new PrMonitor(new SharedStore(store.directory), options);
  const watch = a.watch(target, "checks", "/tmp", 3600);
  assert.equal(a.watch(target, "checks", "/tmp", 3600).id, watch.id);
  b.watch(target, "checks", "/tmp", 3600);
  for (let i = 0; i < 3; i++) { now = i * 30_000; await Promise.all([a.tick(), b.tick()]); await b.tick(); }
  assert.equal(polls, 3);
  assert.equal(a.get(watch.id).status, "passed");
  assert.equal(notifications.length, 2);
});
test("cancelling a session subscription leaves other subscribers active", async t => {
  const store = fixture(t); let now = 0;
  const options = { now: () => now, poll: async () => pr(), notify: () => {} };
  const a = new PrMonitor(store, options), b = new PrMonitor(store, options);
  const wa = a.watch(target, "checks", "/tmp", 3600), wb = b.watch(target, "checks", "/tmp", 3600);
  a.cancel(wa.id);
  for (let i = 0; i < 3; i++) { now = i * 30_000; await b.tick(); }
  assert.equal(a.get(wa.id).status, "cancelled");
  assert.equal(b.get(wb.id).status, "passed");
});
test("checks and ready goals share samples, with one waiting-ready transition", async t => {
  const store = fixture(t); let now = 0, ready = false, polls = 0;
  const notices: { watch: WatchSnapshot; terminal: boolean }[] = [];
  const manager = new PrMonitor(store, { now: () => now, poll: async () => { polls++; return pr({ labels: ready ? [{ name: "ready" }] : [] }); }, notify: (watch, terminal) => notices.push({ watch, terminal }) });
  const checks = manager.watch(target, "checks", "/tmp", 3600), label = manager.watch(target, "ready", "/tmp", 86400);
  for (let i = 0; i < 4; i++) { now = i * 30_000; await manager.tick(); }
  assert.equal(manager.get(checks.id).status, "passed");
  assert.equal(manager.get(label.id).status, "watching");
  assert.equal(notices.length, 2);
  ready = true; now += 30_000; await manager.tick();
  assert.equal(manager.get(label.id).status, "ready");
  assert.equal(notices.length, 3);
  assert.equal(polls, 5);
});
test("a late subscriber waits for a fresh sample, not cached green", async t => {
  const store = fixture(t); let now = 0, raw = pr();
  const options = { now: () => now, poll: async () => raw, notify: () => {} };
  const a = new PrMonitor(store, options);
  a.watch(target, "checks", "/tmp", 3600);
  for (let i = 0; i < 3; i++) { now = i * 30_000; await a.tick(); }
  now++;
  const b = new PrMonitor(store, options), watch = b.watch(target, "checks", "/tmp", 3600);
  raw = pr({ headRefOid: "b".repeat(40) });
  await b.tick(); assert.equal(b.get(watch.id).status, "watching");
  now = 90_000; await b.tick(); assert.equal(b.get(watch.id).status, "head_changed");
});
test("timeouts are per subscription and notify once", async t => {
  const store = fixture(t); let now = 0, notifications = 0;
  const manager = new PrMonitor(store, { now: () => now, poll: async () => pr(), notify: () => { notifications++; } });
  const watch = manager.watch(target, "checks", "/tmp", 1);
  now = 1000; await manager.tick(); await manager.tick();
  assert.equal(manager.get(watch.id).status, "timeout"); assert.equal(notifications, 1);
});
test("shutdown aborts an owned poll and releases its lock without notifying", async t => {
  const store = fixture(t); let release: (() => void) | undefined, notifications = 0;
  const manager = new PrMonitor(store, { notify: () => { notifications++; }, poll: async (_target, _cwd, signal) => new Promise((_resolve, reject) => {
    signal.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
    release = () => manager.shutdown();
  }) });
  manager.watch(target, "checks", "/tmp", 3600);
  const ticking = manager.tick(); assert.ok(release); release(); await ticking;
  assert.equal(notifications, 0);
  const unlock = store.acquire(target.key); assert.ok(unlock); unlock();
  assert.throws(() => manager.watch(target, "checks", "/tmp", 3600));
});
test("poll failures are shared and notify once after three attempts", async t => {
  const store = fixture(t); let now = 0, notices = 0;
  const manager = new PrMonitor(store, { now: () => now, poll: async () => { throw new Error("auth failed"); }, notify: () => { notices++; } });
  const watch = manager.watch(target, "checks", "/tmp", 3600);
  for (let i = 0; i < 4; i++) { now = i * 30_000; await manager.tick(); }
  assert.equal(manager.get(watch.id).status, "error"); assert.equal(notices, 1);
});

test("a poll finishing after the subscriber's deadline reports timeout, not success", async t => {
  const store = fixture(t); let now = 0;
  const manager = new PrMonitor(store, { now: () => now, poll: async () => { now = 2000; return pr({ state: "MERGED" }); }, notify: () => {} });
  const watch = manager.watch(target, "checks", "/tmp", 1);
  await manager.tick(); assert.equal(manager.get(watch.id).status, "timeout");
});

test("two actual Pi-like processes share exactly three polls for one head", async t => {
  const store = fixture(t);
  const managerUrl = new URL("./manager.ts", import.meta.url).href;
  const storeUrl = new URL("./store.ts", import.meta.url).href;
  const code = `
    import fs from 'node:fs';
    import { PrMonitor } from ${JSON.stringify(managerUrl)};
    import { SharedStore } from ${JSON.stringify(storeUrl)};
    const [dir, targetJson, rawJson] = process.argv.slice(1);
    const target = JSON.parse(targetJson), raw = JSON.parse(rawJson);
    const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
    const manager = new PrMonitor(new SharedStore(dir), { intervalMs: 50, notify() {}, poll: async () => {
      fs.appendFileSync(dir + '/polls.log', process.pid + '\\n');
      await wait(40); return raw;
    }});
    const watch = manager.watch(target, 'checks', dir, 5);
    fs.writeFileSync(dir + '/' + process.pid + '.ready', '');
    const deadline = Date.now() + 4000;
    while (fs.readdirSync(dir).filter(name => name.endsWith('.ready')).length < 2) {
      if (Date.now() > deadline) throw new Error('process barrier timed out');
      await wait(10);
    }
    while (manager.get(watch.id).status === 'watching') { await manager.tick(); await wait(10); }
    if (manager.get(watch.id).status !== 'passed') throw new Error('unexpected watch outcome');
    manager.shutdown(); process.stdout.write('passed\\n');
  `;
  const run = () => promisify(execFile)(process.execPath, ["--input-type=module", "-e", code, store.directory, JSON.stringify(target), JSON.stringify(pr())], { timeout: 6000 });
  const results = await Promise.all([run(), run()]);
  assert.ok(results.every(result => result.stdout === "passed\n"));
  assert.equal(fs.readFileSync(path.join(store.directory, "polls.log"), "utf8").trim().split("\n").length, 3);
});
