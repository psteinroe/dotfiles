import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
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

test(
  "fails when a clean parent exit leaves a descendant holding stdio",
  { skip: process.platform === "win32" },
  async () => {
    const manager = new TerminalManager();
    try {
      const task = manager.start({
        command: '(trap "" TERM; while :; do sleep 1; done) & printf PARENT_OK',
        title: "orphaned stdio",
        cwd: process.cwd(),
      });
      await waitForSettlement(manager, [task.id]);
      const settled = manager.get(task.id);
      assert.equal(settled?.status, "failed");
      assert.equal(settled?.exitCode, 0);
      assert.equal(settled?.stdout.text, "PARENT_OK");
      assert.match(settled?.errorText ?? "", /stdio did not close after exit/);
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

test("disposeAll kills a detached descendant carrying the terminal environment", async () => {
  if (process.platform === "win32") return;
  const directory = await mkdtemp(path.join(tmpdir(), "pi-background-terminals-"));
  const fixture = path.join(directory, "detached-child.js");
  const pidFile = path.join(directory, "child.pid");
  await writeFile(
    fixture,
    `const { spawn } = require("node:child_process");
const { writeFileSync } = require("node:fs");
const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], {
  detached: true,
  stdio: "ignore",
});
writeFileSync(process.argv[2], String(child.pid));
child.unref();
setInterval(() => {}, 1000);
`,
  );

  const manager = new TerminalManager();
  let childPid: number | undefined;
  const processIsAlive = (pid: number): boolean => {
    try {
      process.kill(pid, 0);
    } catch {
      return false;
    }
    if (process.platform === "linux") {
      try {
        const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
        if (stat.match(/^\d+ \\(.*\\) ([Zz]) /)) return false;
      } catch {
        return false;
      }
    }
    return true;
  };
  try {
    const task = manager.start({
      command: `${JSON.stringify(process.execPath)} ${JSON.stringify(fixture)} ${JSON.stringify(pidFile)}`,
      title: "detached descendant",
      cwd: directory,
    });
    const deadline = Date.now() + 5_000;
    while (Date.now() < deadline) {
      try {
        childPid = Number(await readFile(pidFile, "utf8"));
        if (childPid > 1) break;
      } catch {
        // The fixture has not spawned its child yet.
      }
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert.ok(childPid && childPid > 1, "fixture did not publish its child pid");
    assert.ok(processIsAlive(childPid), "fixture child exited before shutdown");
    await manager.disposeAll();
    const deadDeadline = Date.now() + 5_000;
    while (processIsAlive(childPid) && Date.now() < deadDeadline) {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    assert.equal(processIsAlive(childPid), false, "detached child survived disposeAll");
    assert.notEqual(manager.get(task.id)?.status, "running");
  } finally {
    await manager.disposeAll();
    if (childPid !== undefined && processIsAlive(childPid)) {
      try {
        process.kill(childPid, "SIGKILL");
      } catch {
        // The fail-safe cleanup target may already have exited.
      }
    }
    await rm(directory, { recursive: true, force: true });
  }
});

test("disposeAll kills a detached native sleep without a visible marker", async () => {
  if (process.platform === "win32") return;
  const directory = await mkdtemp(path.join(tmpdir(), "pi-background-terminals-"));
  const fixture = path.join(directory, "detached-sleep.js");
  const pidFile = path.join(directory, "sleep.pid");
  await writeFile(
    fixture,
    `const { spawn } = require("node:child_process");
const { writeFileSync } = require("node:fs");
const child = spawn("/bin/sleep", ["30"], { detached: true, stdio: "ignore" });
setTimeout(() => {
  if (child.pid === undefined) throw new Error("sleep did not provide a pid");
  process.kill(child.pid, "SIGSTOP");
  writeFileSync(process.argv[2], String(child.pid));
}, 100);
child.unref();
setInterval(() => {}, 1000);
`,
  );

  const manager = new TerminalManager();
  let sleepPid: number | undefined;
  const processIsAlive = (pid: number): boolean => {
    try {
      process.kill(pid, 0);
    } catch {
      return false;
    }
    if (process.platform === "linux") {
      try {
        const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
        if (stat.match(/^\d+ \\(.*\\) ([Zz]) /)) return false;
      } catch {
        return false;
      }
    }
    return true;
  };
  try {
    const task = manager.start({
      command: `${JSON.stringify(process.execPath)} ${JSON.stringify(fixture)} ${JSON.stringify(pidFile)}`,
      title: "detached native sleep",
      cwd: directory,
    });
    const deadline = Date.now() + 5_000;
    while (Date.now() < deadline) {
      try {
        sleepPid = Number(await readFile(pidFile, "utf8"));
        if (sleepPid > 1) break;
      } catch {
        // The fixture has not spawned its child yet.
      }
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    assert.ok(sleepPid && sleepPid > 1, "fixture did not publish its sleep pid");
    assert.ok(processIsAlive(sleepPid), "native sleep exited before shutdown");
    await manager.disposeAll();
    const deadDeadline = Date.now() + 5_000;
    while (processIsAlive(sleepPid) && Date.now() < deadDeadline) {
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    assert.equal(processIsAlive(sleepPid), false, "detached native sleep survived disposeAll");
    assert.notEqual(manager.get(task.id)?.status, "running");
  } finally {
    await manager.disposeAll();
    if (sleepPid !== undefined && processIsAlive(sleepPid)) {
      try {
        process.kill(sleepPid, "SIGKILL");
      } catch {
        // The fail-safe cleanup target may already have exited.
      }
    }
    await rm(directory, { recursive: true, force: true });
  }
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
