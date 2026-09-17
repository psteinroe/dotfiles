import assert from "node:assert/strict";
import test from "node:test";
import { TaskDelivery } from "./delivery.ts";
import type { TaskSnapshot } from "./registry.ts";

function snapshot(id: string): TaskSnapshot {
  return {
    id,
    kind: "command",
    command: "printf done",
    title: id,
    cwd: process.cwd(),
    status: "done",
    createdAt: Date.now(),
    settledAt: Date.now(),
    resultText: "done",
  };
}

async function waitFor(predicate: () => boolean) {
  const deadline = Date.now() + 500;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error("Timed out waiting for delivery");
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
}

const collectIds = (target: string[]) => (results: TaskSnapshot[]) => {
  target.push(...results.map((result) => result.id));
};

test("delivers only after idle, batches pending tasks, and deduplicates ids", async () => {
  const delivered: string[] = [];
  const batches: string[][] = [];
  const delivery = new TaskDelivery(
    (results) => {
      batches.push(results.map((result) => result.id));
      collectIds(delivered)(results);
    },
    { quietMs: 5, retryMs: 5 },
  );

  delivery.setBusy();
  delivery.enqueue(snapshot("busy"));
  await new Promise((resolve) => setTimeout(resolve, 15));
  assert.deepEqual(delivered, []);

  delivery.enqueue(snapshot("duplicate"));
  delivery.enqueue(snapshot("duplicate"));
  delivery.setIdle();
  await waitFor(() => delivered.length === 2);
  assert.deepEqual(delivered, ["busy", "duplicate"]);
  assert.deepEqual(batches, [["busy", "duplicate"]]);
  delivery.shutdown();
});

test("consumption suppresses a queued result", async () => {
  const delivered: string[] = [];
  const delivery = new TaskDelivery(collectIds(delivered), { quietMs: 5 });
  delivery.enqueue(snapshot("consumed"));
  delivery.consume("consumed");
  await new Promise((resolve) => setTimeout(resolve, 15));
  assert.deepEqual(delivered, []);
  delivery.shutdown();
});

test("retries a transient batched send failure while idle", async () => {
  const attempts: string[] = [];
  let calls = 0;
  const delivery = new TaskDelivery(
    (results) => {
      calls++;
      collectIds(attempts)(results);
      if (calls === 1) throw new Error("temporary send failure");
    },
    { quietMs: 5, retryMs: 5 },
  );

  delivery.enqueue(snapshot("retry"));
  await waitFor(() => attempts.length === 2);
  assert.deepEqual(attempts, ["retry", "retry"]);
  delivery.shutdown();
});

test("rechecks live safety at flush time and retries without another lifecycle event", async () => {
  const delivered: string[] = [];
  let canDeliver = true;
  const delivery = new TaskDelivery(collectIds(delivered), {
    quietMs: 5,
    retryMs: 5,
    canDeliver: () => canDeliver,
  });

  delivery.enqueue(snapshot("live-state"));
  canDeliver = false;
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.deepEqual(delivered, []);

  canDeliver = true;
  await waitFor(() => delivered.length === 1);
  assert.deepEqual(delivered, ["live-state"]);
  delivery.shutdown();
});

test("requeues a batch when safety changes at the handoff boundary", async () => {
  const delivered: string[] = [];
  let checks = 0;
  const delivery = new TaskDelivery(collectIds(delivered), {
    quietMs: 5,
    retryMs: 5,
    canDeliver: () => ++checks !== 2,
  });
  delivery.enqueue(snapshot("handoff-race"));
  await waitFor(() => delivered.length === 1);
  assert.deepEqual(delivered, ["handoff-race"]);
  assert.ok(checks >= 3);
  delivery.shutdown();
});

test("consumption during a failed in-flight handoff prevents retry", async () => {
  let rejectSend: ((error: Error) => void) | undefined;
  let calls = 0;
  const delivery = new TaskDelivery(
    () => {
      calls++;
      return new Promise<void>((_resolve, reject) => { rejectSend = reject; });
    },
    { quietMs: 5, retryMs: 5 },
  );
  delivery.enqueue(snapshot("in-flight"));
  await waitFor(() => calls === 1 && Boolean(rejectSend));
  delivery.consume("in-flight");
  rejectSend!(new Error("failed after consumption"));
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert.equal(calls, 1);
  delivery.shutdown();
});

test("shutdown cancels queued delivery", async () => {
  const delivered: string[] = [];
  const delivery = new TaskDelivery(collectIds(delivered), { quietMs: 5 });
  delivery.enqueue(snapshot("stale"));
  delivery.shutdown();
  await new Promise((resolve) => setTimeout(resolve, 15));
  assert.deepEqual(delivered, []);
});
