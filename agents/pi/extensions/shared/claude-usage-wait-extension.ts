import { randomUUID } from "node:crypto";
import { createAssistantMessageEventStream, type AssistantMessage, type Model, type SimpleStreamOptions, type TranscriptContext } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { retryClaudeUsage, type UsageWaitUpdate, type WaitDependencies } from "./claude-usage-wait.ts";

type StreamFunction = (model: Model<any>, context: TranscriptContext, options?: SimpleStreamOptions) => ReturnType<typeof createAssistantMessageEventStream>;
export const USAGE_WAIT_ENTRY = "claude-usage-wait";

export function createClaudeUsageWait(pi: ExtensionAPI, clock: Partial<Pick<WaitDependencies, "now" | "random" | "sleep">> = {}) {
  let context: ExtensionContext | undefined;
  let closed = false;
  const active = new Map<AbortController, { id: string; state?: UsageWaitUpdate }>();
  // The bridge's SDK query spans tool turns and retains the first request's
  // signal. Keep those controllers until settlement so shutdown also stops a
  // query parked behind a tool/approval, not just the latest stream callback.
  const controllers = new Set<AbortController>();
  const render = () => {
    const waits = [...active.values()].filter(({ state }) => state?.phase === "waiting" || state?.phase === "countdown");
    const first = waits[0]?.state;
    context?.ui.setStatus(USAGE_WAIT_ENTRY, first
      ? `Claude waiting (${first.window}${first.fallback ? "; reset unknown/stale" : ""}): ${Math.ceil((first.remainingMs ?? 0) / 1000)}s · ${new Date(first.wakeAt!).toISOString()} · wake ${first.attempt}/3${waits.length > 1 ? ` · ${waits.length} requests` : ""} · Esc or /claude-wait-cancel`
      : undefined);
  };
  pi.on("session_start", (_event, ctx) => {
    if (context && context !== ctx) {
      for (const controller of controllers) controller.abort();
      controllers.clear();
    }
    context = ctx;
  });
  pi.on("cache_warming_decision", () => {
    if ([...active.values()].some(({ state }) => state?.phase === "waiting" || state?.phase === "countdown")) {
      return { action: "stop" };
    }
  });
  pi.on("agent_settled", () => { if (active.size === 0) controllers.clear(); });
  pi.on("session_shutdown", () => {
    for (const controller of controllers) controller.abort();
    controllers.clear();
    closed = true;
    try {
      for (const request of active.values()) {
        if (request.state) pi.appendEntry(USAGE_WAIT_ENTRY, { id: request.id, ...request.state, phase: "cancelled" });
      }
    } finally {
      active.clear();
      render();
      context = undefined;
    }
  });
  pi.registerCommand("claude-wait-cancel", {
    description: "Cancel pending Claude usage waits without resuming the turn",
    handler: async (_args, ctx) => {
      let count = 0;
      for (const [controller, request] of active) {
        if (request.state?.phase === "waiting" || request.state?.phase === "countdown") {
          controller.abort(); count++;
        }
      }
      ctx.ui.notify(count ? `Cancelled ${count} Claude usage wait(s).` : "No Claude usage wait is pending.", "info");
    },
  });

  return (streamSimple: StreamFunction): StreamFunction => (model, transcript, options) => {
    const output = createAssistantMessageEventStream();
    const controller = new AbortController();
    controllers.add(controller);
    if (closed) controller.abort();
    const signal = options?.signal ? AbortSignal.any([options.signal, controller.signal]) : controller.signal;
    const owner = context;
    const request: { id: string; state?: UsageWaitUpdate } = { id: randomUUID() };
    active.set(controller, request);
    const emptyMessage: AssistantMessage = {
      role: "assistant", api: model.api, provider: model.provider, model: model.id,
      content: [], stopReason: "pending", timestamp: Date.now(),
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
    };
    void (async () => {
      try {
        for await (const event of retryClaudeUsage(
          (retry) => streamSimple(model, transcript, { ...options, signal, ...(retry ? { claudeUsageRetry: true } : {}) }),
          signal,
          { ...clock, emptyMessage, update: (state) => {
            if (closed || owner !== context) return;
            request.state = state;
            // Audit transitions in real session storage, never context or a cache.
            // They are deliberately NOT replayable jobs: reload/exit requires a
            // new explicit prompt. A crash cannot resurrect cancelled/completed work.
            if (state.phase !== "countdown") {
              pi.appendEntry(USAGE_WAIT_ENTRY, { id: request.id, model: model.id, ...state });
              pi.events.emit(USAGE_WAIT_ENTRY, { id: request.id, model: model.id, ...state });
              if (state.phase === "waiting") {
                const message = `Claude waiting for ${state.window} until ${new Date(state.wakeAt!).toISOString()} (${state.fallback ? "bounded fallback; reset missing/stale" : "SDK reset + safety margin"}); automatic wake ${state.attempt}/3. Cancel with Esc or /claude-wait-cancel.`;
                if (owner?.hasUI) owner.ui.notify(message, "warning");
                else process.stderr.write(`${message}\n`);
              }
            }
            render();
          } },
        )) output.push(event);
      } catch (error) {
        output.push({ type: "error", reason: signal.aborted ? "aborted" : "error", error: {
          ...emptyMessage, stopReason: signal.aborted ? "aborted" : "error",
          errorMessage: signal.aborted ? "Operation aborted" : error instanceof Error ? error.message : String(error),
        } });
      } finally {
        active.delete(controller);
        if (!closed && owner === context) render();
        output.end();
      }
    })();
    return output;
  };
}
