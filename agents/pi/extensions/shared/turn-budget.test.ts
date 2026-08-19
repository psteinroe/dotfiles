import assert from "node:assert/strict";
import test from "node:test";
import { createTurnBudgetExtension } from "./turn-budget.ts";

test("reserves the final bounded turn for a text answer", async () => {
  const handlers = new Map<string, (...args: any[]) => any>();
  const pi = {
    on(name: string, handler: (...args: any[]) => any) {
      handlers.set(name, handler);
    },
  };
  createTurnBudgetExtension(50)(pi as any);

  for (let turnIndex = 0; turnIndex < 49; turnIndex++) {
    await handlers.get("turn_start")?.({ turnIndex });
  }
  assert.equal(await handlers.get("tool_call")?.(), undefined);
  const result = await handlers.get("tool_result")?.({
    content: [{ type: "text", text: "result" }],
  });
  assert.match(result.content.at(-1).text, /turn 49\/50; remaining after this turn: 1/);

  // Pi can reset its event turnIndex after an internal retry. The child budget
  // remains cumulative for the lifetime of this session.
  await handlers.get("turn_start")?.({ turnIndex: 0 });
  const blocked = await handlers.get("tool_call")?.();
  assert.equal(blocked.block, true);
  assert.match(blocked.reason, /final turn \(turn 50\/50\)/);
  assert.match(blocked.reason, /final answer now without calling tools/);
});
