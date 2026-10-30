import type { AgentSession } from "@earendil-works/pi-coding-agent";
import type { Model } from "./subagent-models.ts";
import type { SubagentRunDetails } from "./subagent-progress.ts";

type SubagentSession = Pick<AgentSession, "messages" | "model" | "prompt" | "setModel" | "setThinkingLevel">;
interface PromptOptions {
  models: Model[];
  thinkingLevel: Parameters<AgentSession["setThinkingLevel"]>[0];
  signal?: AbortSignal;
  run: SubagentRunDetails;
  onModelChange?: (model: Model) => void;
}

/** Provider diagnostics must not expose credentials. */
function safeError(error: unknown): string {
  return (error instanceof Error ? error.message : String(error))
    .replace(/\b(?:Bearer|Basic)\s+\S+/gi, "[redacted authorization]")
    .replace(/((?:api[_-]?key|authorization|cookie|set-cookie)["']?\s*[:=]\s*)[^\r\n]+/gi, "$1[redacted]")
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, "[redacted token]")
    .replace(/\bsk-[A-Za-z0-9_-]+\b/g, "[redacted key]")
    .replace(/((?:access|refresh|id)[_-]?token["']?\s*[:=]\s*["']?)[^\s"',}]+/gi, "$1[redacted]")
    .slice(0, 2000);
}

function checkStopped(options: PromptOptions, enforceBudget = true): void {
  const { run } = options;
  if (options.signal?.aborted || run.terminationReason === "cancelled" || run.terminationReason === "shutdown") {
    run.terminationReason ??= "cancelled";
    const error = new Error("Subagent was aborted.");
    error.name = "AbortError";
    throw error;
  }
  if (run.terminationReason === "turn_limit" || (enforceBudget && run.maxTurns !== undefined && run.turns >= run.maxTurns)) {
    run.terminationReason = "turn_limit";
    throw new Error(`Subagent reached its ${run.maxTurns ?? "configured"}-turn limit.`);
  }
}

/** One child, one provider, one submission. Pi owns transient request retries. */
export async function promptSubagent(
  session: SubagentSession,
  prompt: string,
  options: PromptOptions,
): Promise<void> {
  if (options.models.length !== 1) throw new Error("A subagent requires exactly one selected model.");
  checkStopped(options);
  const model = options.models[0];
  try {
    if (session.model?.provider !== model.provider || session.model.id !== model.id) {
      await session.setModel(model);
    }
    checkStopped(options);
    session.setThinkingLevel(options.thinkingLevel);
    options.onModelChange?.(model);
    const startIndex = session.messages.length;
    await session.prompt(prompt, { expandPromptTemplates: false });
    // A final answer on the last permitted turn is still a successful result.
    checkStopped(options, false);
    const last = session.messages.slice(startIndex).reverse().find((message) => message.role === "assistant");
    if (last?.role === "assistant" && last.stopReason === "aborted") {
      options.run.terminationReason ??= "cancelled";
      checkStopped(options);
    }
    if (last?.role === "assistant" && last.stopReason === "error") {
      throw new Error(last.errorMessage || "Provider returned an error without diagnostics.");
    }
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") options.run.terminationReason ??= "cancelled";
    checkStopped(options);
    throw new Error(safeError(error));
  }
}
