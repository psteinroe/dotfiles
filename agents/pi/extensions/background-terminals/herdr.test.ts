import assert from "node:assert/strict";
import test from "node:test";
import {
  createHerdrBackgroundHold,
  HERDR_BACKGROUND_LABEL,
  type HerdrBlockedEvent,
} from "./src/herdr.ts";

test("holds Herdr non-idle from foreground settlement until the last terminal settles", () => {
  const events: HerdrBlockedEvent[] = [];
  const hold = createHerdrBackgroundHold((event) => events.push(event));

  hold.setForegroundActive(true);
  hold.updateRunning(1);
  hold.updateRunning(2);
  assert.deepEqual(events, [], "foreground work remains Herdr's authority");

  hold.setForegroundActive(false);
  hold.updateRunning(1);
  hold.updateRunning(0);
  hold.updateRunning(0);

  assert.deepEqual(events, [
    { active: true, label: HERDR_BACKGROUND_LABEL },
    { active: false, label: undefined },
  ]);
});

test("foreground work temporarily releases and then reacquires the hold", () => {
  const events: HerdrBlockedEvent[] = [];
  const hold = createHerdrBackgroundHold((event) => events.push(event));

  hold.updateRunning(1);
  hold.setForegroundActive(true);
  hold.setForegroundActive(false);
  hold.updateRunning(0);

  assert.deepEqual(
    events.map((event) => event.active),
    [true, false, true, false],
  );
});
