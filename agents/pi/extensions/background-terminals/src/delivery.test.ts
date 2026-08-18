import assert from "node:assert/strict";
import test from "node:test";
import { BackgroundTerminalDelivery } from "./delivery.ts";
import type { TerminalSnapshot } from "./manager.ts";

function snapshot(id: string): TerminalSnapshot {
  return {
    id,
    command: "printf done",
    title: id,
    cwd: process.cwd(),
    status: "done",
    createdAt: Date.now(),
    settledAt: Date.now(),
    exitCode: 0,
    stdout: { text: "done", totalBytes: 4, truncatedBytes: 0 },
    stderr: { text: "", totalBytes: 0, truncatedBytes: 0 },
  };
}

async function waitFor(predicate: () => boolean) {
  const deadline = Date.now() + 500;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error("Timed out waiting for delivery");
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
}

test("delivers only after an idle transition and never duplicates an id", async () => {
  const delivered: string[] = [];
  const delivery = new BackgroundTerminalDelivery(
    (result) => delivered.push(result.id),
    { quietMs: 5, retryMs: 5 },
  );

  delivery.setBusy();
  delivery.enqueue(snapshot("busy"));
  await new Promise((resolve) => setTimeout(resolve, 15));
  assert.deepEqual(delivered, []);

  delivery.setIdle();
  delivery.enqueue(snapshot("duplicate"));
  delivery.enqueue(snapshot("duplicate"));
  await waitFor(() => delivered.length === 2);
  assert.deepEqual(delivered, ["busy", "duplicate"]);
  delivery.shutdown();
});

test("consumption suppresses a queued result", async () => {
  const delivered: string[] = [];
  const delivery = new BackgroundTerminalDelivery(
    (result) => delivered.push(result.id),
    { quietMs: 5 },
  );
  delivery.enqueue(snapshot("consumed"));
  delivery.consume("consumed");
  await new Promise((resolve) => setTimeout(resolve, 15));
  assert.deepEqual(delivered, []);
  delivery.shutdown();
});

test("retries a transient send failure while idle", async () => {
  const attempts: string[] = [];
  const delivery = new BackgroundTerminalDelivery(
    (result) => {
      attempts.push(result.id);
      if (attempts.length === 1) throw new Error("temporary send failure");
    },
    { quietMs: 5, retryMs: 5 },
  );

  delivery.enqueue(snapshot("retry"));
  await waitFor(() => attempts.length === 2);
  assert.deepEqual(attempts, ["retry", "retry"]);
  delivery.shutdown();
});

test("shutdown cancels queued delivery", async () => {
  const delivered: string[] = [];
  const delivery = new BackgroundTerminalDelivery(
    (result) => delivered.push(result.id),
    { quietMs: 5 },
  );
  delivery.enqueue(snapshot("stale"));
  delivery.shutdown();
  await new Promise((resolve) => setTimeout(resolve, 15));
  assert.deepEqual(delivered, []);
});
