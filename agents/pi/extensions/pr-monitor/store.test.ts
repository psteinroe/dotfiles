import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawn } from "node:child_process";
import { once } from "node:events";
import test from "node:test";
import { advance, targetFor } from "./state.ts";
import { SharedStore } from "./store.ts";
const target = targetFor("https://github.com/example/project/pull/123", "a".repeat(40));
function fixture(t: test.TestContext) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pr-monitor-lock-test-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  return new SharedStore(dir);
}

test("locks exclude independent stores and cannot be age-stolen from a live PID", t => {
  const a = fixture(t), b = new SharedStore(a.directory);
  const release = a.acquire(target.key); assert.ok(release);
  const lock = path.join(a.directory, `${target.key}.lock`);
  fs.utimesSync(lock, new Date(0), new Date(0));
  assert.equal(b.acquire(target.key), undefined);
  release(); const next = b.acquire(target.key); assert.ok(next); next();
});
test("dead owner and dead reclaimer locks can be recovered", t => {
  const store = fixture(t), lock = path.join(store.directory, `${target.key}.lock`);
  fs.mkdirSync(path.join(lock, "reap"), { recursive: true });
  fs.writeFileSync(path.join(lock, "owner.json"), JSON.stringify({ pid: 2147483647, token: "dead-owner" }));
  fs.writeFileSync(path.join(lock, "reap", "owner.json"), JSON.stringify({ pid: 2147483647, token: "dead-reclaimer" }));
  const release = store.acquire(target.key); assert.ok(release); release();
});
test("missing ownership metadata is not guessed or stolen", t => {
  const store = fixture(t);
  fs.mkdirSync(path.join(store.directory, `${target.key}.lock`));
  // Atomic rename may replace an EMPTY directory, which is not a published monitor lock.
  fs.writeFileSync(path.join(store.directory, `${target.key}.lock`, "unknown"), "uncertain owner");
  assert.equal(store.acquire(target.key), undefined);
});
test("snapshot writes are atomic; invalid keys and corrupt data cannot be trusted", t => {
  const store = fixture(t);
  assert.throws(() => store.acquire("../../elsewhere"));
  const state = advance(target, undefined, { headRefOid: target.head, state: "OPEN", isDraft: false, labels: [], statusCheckRollup: [] }, 123);
  store.write(target.key, state);
  assert.deepEqual(store.read(target.key), state);
  fs.writeFileSync(path.join(store.directory, `${target.key}.json`), "{");
  assert.equal(store.read(target.key), undefined);
});
test("a separate process owns the lock until shutdown, then another process can recover it", async t => {
  const store = fixture(t);
  const moduleUrl = new URL("./store.ts", import.meta.url).href;
  const code = `import { SharedStore } from ${JSON.stringify(moduleUrl)}; const store = new SharedStore(process.argv[1]); const release = store.acquire(process.argv[2]); if (!release) process.exit(2); process.stdout.write('locked\\n'); setInterval(() => {}, 1000);`;
  const child = spawn(process.execPath, ["--input-type=module", "-e", code, store.directory, target.key], { stdio: ["ignore", "pipe", "pipe"] });
  t.after(() => { if (child.exitCode === null) child.kill("SIGKILL"); });
  let stderr = ""; child.stderr.on("data", b => { stderr += b; });
  const [data] = await once(child.stdout, "data");
  assert.equal(String(data), "locked\n", stderr);
  assert.equal(store.acquire(target.key), undefined);
  const exited = once(child, "exit"); child.kill("SIGKILL"); await exited;
  const release = store.acquire(target.key); assert.ok(release); release();
});
