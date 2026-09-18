import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { TaskRegistry } from "./registry.ts";

test("tracks progress, settlement, consumption, and cancellation", async () => {
  const registry = new TaskRegistry();
  const settled: Array<{ id: string; consumed: boolean }> = [];
  registry.onSettle((task, consumed) => settled.push({ id: task.id, consumed }));

  let cancelled = false;
  const task = registry.create({
    kind: "subagent",
    title: "mapper fixture",
    cwd: "/tmp/project",
    agent: "mapper",
    cancel: () => { cancelled = true; },
  });
  assert.equal(task.status, "starting");

  registry.update(task.id, { status: "running", details: { run: { turns: 2 } } });
  assert.equal(registry.get(task.id)?.status, "running");

  registry.consume(task.id);
  registry.settle(task.id, "done", { resultText: "complete" });
  assert.deepEqual(settled, [{ id: task.id, consumed: true }]);
  assert.equal(registry.get(task.id)?.resultText, "complete");

  const second = registry.create({
    kind: "command",
    title: "server",
    cwd: "/tmp/project",
    command: "sleep 60",
    cancel: () => { cancelled = true; },
  });
  assert.equal(registry.cancel(second.id).status, "cancelling");
  assert.equal(registry.update(second.id, { status: "running" }).status, "cancelling");
  await Promise.resolve();
  assert.equal(cancelled, true);
});

test("rejects overlapping live Worker scopes and releases them on settlement", () => {
  const registry = new TaskRegistry();
  const firstScope = registry.assertWriteScopeAvailable("/repo", ["src/auth"]);
  const first = registry.create({
    kind: "subagent",
    title: "worker one",
    cwd: "/repo",
    agent: "worker",
    status: "running",
    writeScope: firstScope,
  });

  assert.throws(
    () => registry.assertWriteScopeAvailable("/repo", ["src/auth/login.ts"]),
    /overlaps task-1/,
  );
  assert.equal(registry.conflictsWithActiveWorker("/repo/src/auth/token.ts")?.id, first.id);
  assert.equal(registry.conflictsWithActiveWorker("/repo/src/payments/index.ts"), undefined);

  registry.settle(first.id, "done");
  assert.deepEqual(
    registry.assertWriteScopeAvailable("/repo", ["src/auth/login.ts"]),
    ["/repo/src/auth/login.ts"],
  );
});

test("prunes acknowledged settled tasks to a bounded history", () => {
  const registry = new TaskRegistry();
  for (let index = 0; index < 80; index++) {
    const task = registry.create({ kind: "command", title: String(index), cwd: "/tmp" });
    registry.settle(task.id, "done");
    registry.consume(task.id);
  }
  assert.equal(registry.list().length, 64);
  assert.equal(registry.get("task-1"), undefined);
  assert.ok(registry.get("task-80"));
});

test("rejects repository-wide and out-of-repository Worker scopes", () => {
  const registry = new TaskRegistry();
  assert.throws(() => registry.assertWriteScopeAvailable("/repo", ["."]), /entire repository/);
  assert.throws(() => registry.assertWriteScopeAvailable("/repo", ["../outside"]), /stay inside/);
});

test("canonicalizes symlink aliases before checking Worker overlap", () => {
  const root = mkdtempSync(join(tmpdir(), "worker-scope-"));
  const real = join(root, "real");
  const alias = join(root, "alias");
  mkdirSync(real);
  symlinkSync(real, alias);
  try {
    const registry = new TaskRegistry();
    const task = registry.create({
      kind: "subagent",
      title: "worker",
      cwd: root,
      agent: "worker",
      status: "running",
      writeScope: registry.assertWriteScopeAvailable(root, ["real"]),
    });
    assert.equal(registry.conflictsWithActiveWorker(join(alias, "file.ts"))?.id, task.id);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("shutdown requests cancellation for every active task", async () => {
  const registry = new TaskRegistry();
  const cancelled: string[] = [];
  for (const title of ["one", "two"]) {
    registry.create({
      kind: "command",
      title,
      cwd: "/tmp",
      cancel: () => { cancelled.push(title); },
    });
  }
  await registry.shutdown();
  assert.deepEqual(cancelled.sort(), ["one", "two"]);
  assert.throws(
    () => registry.create({ kind: "command", title: "late", cwd: "/tmp" }),
    /shutting down/,
  );
});
