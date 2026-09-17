import assert from "node:assert/strict";
import { test } from "node:test";
import { MAX_RUNNING, TerminalManager } from "./src/manager.ts";

async function waitForSettlement(manager: TerminalManager, ids: string[]): Promise<void> {
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    if (ids.every((id) => manager.get(id)?.status !== "running")) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(`background terminals did not settle: ${ids.join(", ")}`);
}

test("runs multiple background terminals concurrently", async () => {
  const manager = new TerminalManager();
  try {
    const first = manager.start({ command: "sleep 0.2; printf first", title: "first", cwd: process.cwd() });
    const second = manager.start({ command: "sleep 0.2; printf second", title: "second", cwd: process.cwd() });

    assert.equal(manager.runningCount(), 2);
    await waitForSettlement(manager, [first.id, second.id]);
    assert.equal(manager.get(first.id)?.status, "done");
    assert.equal(manager.get(second.id)?.status, "done");
    assert.equal(manager.get(first.id)?.stdout.text, "first");
    assert.equal(manager.get(second.id)?.stdout.text, "second");
  } finally {
    await manager.disposeAll();
  }
});

test(
  "supports pipefail in POSIX background commands",
  { skip: process.platform === "win32" },
  async () => {
    const manager = new TerminalManager();
    try {
      const terminal = manager.start({
        command: "set -o pipefail; printf ok",
        title: "pipefail",
        cwd: process.cwd(),
      });

      await waitForSettlement(manager, [terminal.id]);
      assert.equal(manager.get(terminal.id)?.status, "done");
      assert.equal(manager.get(terminal.id)?.stdout.text, "ok");
      assert.equal(manager.get(terminal.id)?.stderr.text, "");
    } finally {
      await manager.disposeAll();
    }
  },
);

test(
  "propagates pipeline failures when pipefail is enabled",
  { skip: process.platform === "win32" },
  async () => {
    const manager = new TerminalManager();
    try {
      const terminal = manager.start({
        command: "set -o pipefail; false | true",
        title: "failing pipeline",
        cwd: process.cwd(),
      });

      await waitForSettlement(manager, [terminal.id]);
      assert.equal(manager.get(terminal.id)?.status, "failed");
      assert.equal(manager.get(terminal.id)?.exitCode, 1);
    } finally {
      await manager.disposeAll();
    }
  },
);

test("classifies a TERM-trapping zero exit as cancelled", async () => {
  if (process.platform === "win32") return;
  const manager = new TerminalManager();
  try {
    const task = manager.start({
      command: "trap 'exit 0' TERM; while :; do sleep 0.1; done",
      title: "term trap",
      cwd: process.cwd(),
    });
    await new Promise((resolve) => setTimeout(resolve, 30));
    const settled = await manager.kill(task.id);
    assert.equal(settled.status, "killed");
  } finally {
    await manager.disposeAll();
  }
});

test("disposeAll waits for stubborn process tasks to settle", async () => {
  if (process.platform === "win32") return;
  const manager = new TerminalManager();
  const task = manager.start({
    command: "trap '' TERM; while :; do sleep 0.1; done",
    title: "stubborn",
    cwd: process.cwd(),
  });
  await new Promise((resolve) => setTimeout(resolve, 30));
  const count = await manager.disposeAll();
  assert.equal(count, 1);
  assert.notEqual(manager.get(task.id)?.status, "running");
});

test("enforces the eight-terminal parallel limit", async () => {
  const manager = new TerminalManager();
  try {
    for (let index = 0; index < MAX_RUNNING; index++) {
      manager.start({ command: "sleep 10", title: `task-${index}`, cwd: process.cwd() });
    }

    assert.equal(manager.runningCount(), MAX_RUNNING);
    assert.throws(
      () => manager.start({ command: "sleep 10", title: "overflow", cwd: process.cwd() }),
      /Max 8 background commands/,
    );
  } finally {
    await manager.disposeAll();
  }
});
