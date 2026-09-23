import assert from "node:assert/strict";
import test from "node:test";
import { TaskSteering } from "./steering.ts";

test("steers only live streaming children and removes their handles on completion", async () => {
  const steering = new TaskSteering();
  const received: string[] = [];
  const session = { isStreaming: false, async steer(message: string) { received.push(message); } };
  const remove = steering.register("task-1", session);

  await assert.rejects(steering.steer("task-1", "new direction"), /not currently processing/);
  session.isStreaming = true;
  await steering.steer("task-1", "new direction");
  assert.deepEqual(received, ["new direction"]);

  remove();
  await assert.rejects(steering.steer("task-1", "too late"), /not currently processing/);
  assert.deepEqual(received, ["new direction"]);
});

test("stale cleanup cannot remove a replacement session, and shutdown clears handles", async () => {
  const steering = new TaskSteering();
  const received: string[] = [];
  const old = steering.register("task-1", { isStreaming: true, async steer() { received.push("old"); } });
  steering.register("task-1", { isStreaming: true, async steer() { received.push("new"); } });
  old();
  await steering.steer("task-1", "next");
  assert.deepEqual(received, ["new"]);
  steering.clear();
  await assert.rejects(steering.steer("task-1", "next"), /not currently processing/);
});
