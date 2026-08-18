import assert from "node:assert/strict";
import test from "node:test";
import { createTurnBudgetExtension } from "./turn-budget.ts";

test("blocks final-turn tools and annotates tool results with remaining budget", async () => {
  const handlers = new Map<string, (...args: any[]) => any>();
  const pi = {
    on(name: string, handler: (...args: any[]) => any) {
      handlers.set(name, handler);
    },
  };
  createTurnBudgetExtension(10)(pi as any);

  await handlers.get("turn_start")?.({ turnIndex: 8 });
  assert.equal(await handlers.get("tool_call")?.(), undefined);
  const result = await handlers.get("tool_result")?.({
    content: [{ type: "text", text: "result" }],
  });
  assert.match(result.content.at(-1).text, /turn 9\/10; remaining after this turn: 1/);

  await handlers.get("turn_start")?.({ turnIndex: 9 });
  const blocked = await handlers.get("tool_call")?.();
  assert.equal(blocked.block, true);
  assert.match(blocked.reason, /final turn \(turn 10\/10\)/);
});
