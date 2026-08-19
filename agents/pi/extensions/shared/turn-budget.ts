import type { ExtensionFactory } from "@earendil-works/pi-coding-agent";

/** Reserve the final bounded turn for a text answer by blocking further tools. */
export function createTurnBudgetExtension(maxTurns: number): ExtensionFactory {
  return (pi) => {
    let turnsStarted = 0;

    pi.on("turn_start", async () => {
      turnsStarted++;
    });

    pi.on("tool_call", async () => {
      if (turnsStarted < maxTurns) return undefined;
      const humanTurn = Math.min(turnsStarted, maxTurns);
      return {
        block: true,
        reason: `Tool use is disabled on the final turn (turn ${humanTurn}/${maxTurns}). Provide your final answer now without calling tools.`,
      };
    });

    pi.on("tool_result", async (event) => {
      const remainingAfter = Math.max(0, maxTurns - turnsStarted);
      const humanTurn = Math.min(turnsStarted, maxTurns);
      const budgetLine = `[turn budget] turn ${humanTurn}/${maxTurns}; remaining after this turn: ${remainingAfter}`;
      return {
        content: [...(event.content ?? []), { type: "text", text: `\n\n${budgetLine}` }],
      };
    });
  };
}
