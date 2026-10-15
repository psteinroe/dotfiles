import { setTimeout as delay } from "node:timers/promises";
import type { AssistantMessage, AssistantMessageEvent } from "@earendil-works/pi-ai";

const FALLBACK_MS = [60_000, 120_000, 300_000];
const WINDOWS = new Map([
  ["five_hour", 6 * 3600_000],
  ...["seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_overage_included"]
    .map((name) => [name, 8 * 24 * 3600_000] as const),
]);
export interface UsageWaitPlan {
  window: string;
  wakeAt: number;
  resetAt?: number;
  fallback: boolean;
}
export interface UsageWaitUpdate extends Partial<UsageWaitPlan> {
  phase: "waiting" | "countdown" | "retrying" | "finished" | "cancelled" | "stopped";
  attempt: number;
  remainingMs?: number;
}
export interface WaitDependencies {
  now: () => number;
  random: () => number;
  sleep: (ms: number, signal: AbortSignal) => Promise<unknown>;
  update: (state: UsageWaitUpdate) => void;
  emptyMessage?: AssistantMessage;
}

/** SDK resetsAt is Unix seconds. Never parse localized prose or guess units. */
export function planClaudeUsageWait(info: unknown, now: number, attempt: number, random: number): UsageWaitPlan | undefined {
  if (!info || typeof info !== "object") return;
  const data = info as Record<string, unknown>;
  const horizon = WINDOWS.get(data.rateLimitType as string);
  if (data.status !== "rejected" || !horizon || data.errorCode || data.limitScope) return;
  const resetAt = typeof data.resetsAt === "number" ? data.resetsAt * 1000 : NaN;
  const valid = Number.isFinite(resetAt) && resetAt > now && resetAt <= now + horizon;
  const margin = 5000 + Math.floor(Math.max(0, Math.min(1, random)) * 5000);
  return {
    window: data.rateLimitType as string,
    wakeAt: (valid ? resetAt : now + FALLBACK_MS[Math.min(attempt, FALLBACK_MS.length - 1)]) + margin,
    resetAt: valid ? resetAt : undefined,
    fallback: !valid,
  };
}

/**
 * Own only one pending provider request, not the agent loop. Completed tool turns
 * have already returned to Pi and are never re-run here. Empty failed attempts
 * do not enter session/model history or consume Pi's generic retry budget.
 */
export async function* retryClaudeUsage(
  attemptStream: (retry: boolean) => AsyncIterable<AssistantMessageEvent>,
  signal: AbortSignal,
  injected: Partial<WaitDependencies> = {},
): AsyncGenerator<AssistantMessageEvent> {
  const deps: WaitDependencies = {
    now: Date.now, random: Math.random,
    sleep: (ms, abort) => delay(ms, undefined, { signal: abort }),
    update: () => {}, ...injected,
  };
  let attempt = 0;
  let last: AssistantMessage | undefined = deps.emptyMessage;
  let waiting = false;
  const update = (phase: UsageWaitUpdate["phase"], plan?: UsageWaitPlan) => {
    deps.update({ phase, attempt, ...plan, remainingMs: plan ? Math.max(0, plan.wakeAt - deps.now()) : undefined });
  };
  try {
    while (true) {
      signal.throwIfAborted();
      let failure: Extract<AssistantMessageEvent, { type: "error" }> | undefined;
      let success: Extract<AssistantMessageEvent, { type: "done" }> | undefined;
      let start: Extract<AssistantMessageEvent, { type: "start" }> | undefined;
      let contentEmitted = false;
      // Fully drain each source before retry: the bridge's finally must release
      // SDK/MCP routing state before another call can claim it.
      for await (const event of attemptStream(attempt > 0)) {
        if (event.type === "error") {
          failure = event;
          last = event.error;
        } else if (event.type === "done") {
          success = event;
          last = event.message;
        } else if (event.type === "start" && !contentEmitted) {
          start = event;
        } else {
          if (start) { yield start; start = undefined; }
          contentEmitted = true;
          yield event;
        }
      }
      signal.throwIfAborted();
      if (!failure) {
        if (!success) throw new Error("Claude Bridge stream ended without a terminal event.");
        if (waiting) update("finished");
        if (start) yield start;
        yield success;
        return;
      }
      const info = (failure.error as AssistantMessage & { claudeUsageLimit?: unknown }).claudeUsageLimit;
      const plan = planClaudeUsageWait(info, deps.now(), attempt, deps.random());
      if (!plan) {
        if (waiting) update("stopped");
        if (start) yield start;
        yield failure;
        return;
      }
      // A failed partial stream has no safe replay contract. Keep its content
      // exactly as received and stop rather than executing/repeating tool calls.
      if (contentEmitted || failure.error.content.length > 0 || attempt >= FALLBACK_MS.length) {
        update("stopped");
        if (start) yield start;
        yield { ...failure, error: { ...failure.error,
          errorMessage: contentEmitted || failure.error.content.length > 0
            ? "Claude usage recovery stopped: interrupted response contains content. Inspect it before continuing."
            : `Claude usage wait stopped after ${attempt} wake-ups. Send a new prompt to try again.`,
        } };
        return;
      }
      waiting = true;
      attempt++;
      update("waiting", plan);
      while (deps.now() < plan.wakeAt) {
        signal.throwIfAborted();
        await deps.sleep(Math.min(15_000, plan.wakeAt - deps.now()), signal);
        update("countdown", plan);
      }
      signal.throwIfAborted();
      update("retrying", plan);
    }
  } catch (error) {
    if (!signal.aborted) throw error;
    update("cancelled");
    yield { type: "error", reason: "aborted", error: {
      ...last!, content: last?.content ?? [], stopReason: "aborted", errorMessage: "Operation aborted",
    } };
  }
}
