import type { AssistantMessage } from "@earendil-works/pi-ai";
import type {
  AgentSession,
  AgentSessionEvent,
} from "@earendil-works/pi-coding-agent";
import {
  bindChildSessionExtensions,
  shutdownAndDisposeChildSession,
  type DisposableChildSession,
} from "./child-session.ts";
import {
  MAX_TOOL_CALLS_TO_KEEP,
  type SubagentRunDetails,
} from "./subagent-progress.ts";

export { bindChildSessionExtensions, shutdownAndDisposeChildSession } from "./child-session.ts";
export type { DisposableChildSession } from "./child-session.ts";

function assistantMessageText(message: AssistantMessage): string {
  return message.content
    .filter((part) => part.type === "text")
    .map((part) => part.text)
    .join("\n")
    .trim();
}

/** Extract the last non-empty assistant text, ignoring thinking/tool parts. */
export function extractAssistantText(
  session: Pick<AgentSession, "messages">,
): string {
  for (let index = session.messages.length - 1; index >= 0; index--) {
    const message = session.messages[index];
    if ((message as { role?: string }).role !== "assistant") continue;
    const text = assistantMessageText(message as AssistantMessage);
    if (text) return text;
  }
  return "";
}

/** Extract text only from the latest assistant response. */
export function extractLatestAssistantText(
  session: Pick<AgentSession, "messages">,
): string {
  for (let index = session.messages.length - 1; index >= 0; index--) {
    const message = session.messages[index];
    if ((message as { role?: string }).role === "assistant") {
      return assistantMessageText(message as AssistantMessage);
    }
  }
  return "";
}

/** Explain missing text without hiding a bounded run that exhausted its budget. */
export function describeMissingSubagentOutput(
  agent: string,
  run: Pick<SubagentRunDetails, "turns" | "maxTurns" | "terminationReason">,
) {
  const label = agent.charAt(0).toUpperCase() + agent.slice(1);
  if (
    run.maxTurns !== undefined
    && (run.terminationReason === "turn_limit" || run.turns >= run.maxTurns)
  ) {
    return {
      terminationReason: "turn_limit" as const,
      message:
        `${label} reached its ${run.maxTurns}-turn limit after working but did not return a final summary. Review the working-tree diff and recent tool calls.`,
    };
  }
  return {
    terminationReason: "empty_output" as const,
    message: `${label} completed without a final text response.`,
  };
}

export interface SubagentEventTrackingOptions {
  run: SubagentRunDetails;
  /** undefined means unlimited turns and disables soft-limit steering. */
  maxTurns?: number;
  maxToolCalls?: number;
  updateIntervalMs?: number;
  now?: () => number;
  onUpdate?: (force: boolean) => void;
  softLimitPrompt?: string;
}

export interface SubagentEventTracker {
  /** Emit an update unless it is still inside the throttle window. */
  emitUpdate(force?: boolean): void;
  /** Remove the session listener and release the tracker closure. */
  unsubscribe(): void;
}

/**
 * Track the common child events and apply the existing soft turn-limit policy.
 * Tool starts are always immediate; turn-end updates are throttled.
 */
export function trackSubagentEvents(
  session: Pick<AgentSession, "subscribe" | "steer" | "abort">,
  options: SubagentEventTrackingOptions,
): SubagentEventTracker {
  const maxToolCalls = options.maxToolCalls ?? MAX_TOOL_CALLS_TO_KEEP;
  const updateIntervalMs = options.updateIntervalMs ?? 120;
  const now = options.now ?? Date.now;
  const softLimit = options.maxTurns;
  const wrapAtTurn = softLimit === undefined ? undefined : Math.max(1, softLimit - 1);
  const softLimitPrompt = options.softLimitPrompt
    ?? "Your next turn is reserved for the final answer. Stop exploring and return your best concise result without using more tools.";
  let lastUpdate = 0;
  let wrapRequested = false;
  let hardAbortRequested = false;
  let unsubscribed = false;

  const emitUpdate = (force = false) => {
    const timestamp = now();
    if (!force && timestamp - lastUpdate < updateIntervalMs) return;
    lastUpdate = timestamp;
    options.onUpdate?.(force);
  };

  const listener = (event: AgentSessionEvent) => {
    switch (event.type) {
      case "turn_end": {
        options.run.turns++;
        if (
          wrapAtTurn !== undefined
          && options.run.turns >= wrapAtTurn
          && !wrapRequested
        ) {
          wrapRequested = true;
          void session.steer(softLimitPrompt).catch(() => undefined);
        } else if (
          softLimit !== undefined
          && options.run.turns >= softLimit + 2
          && !hardAbortRequested
        ) {
          const endedWithText = (event.message as AssistantMessage | undefined)?.content
            ?.some((part) => part.type === "text" && part.text.trim().length > 0)
            ?? false;
          if (!endedWithText) {
            hardAbortRequested = true;
            options.run.terminationReason = "turn_limit";
            void session.abort().catch(() => undefined);
          }
        }
        emitUpdate();
        break;
      }
      case "tool_execution_start": {
        options.run.toolCalls.push({
          id: event.toolCallId,
          name: event.toolName,
          args: event.args,
          startedAt: now(),
        });
        if (options.run.toolCalls.length > maxToolCalls) {
          options.run.toolCalls.splice(0, options.run.toolCalls.length - maxToolCalls);
        }
        emitUpdate(true);
        break;
      }
      case "tool_execution_end": {
        const call = options.run.toolCalls.find(
          (candidate) => candidate.id === event.toolCallId,
        );
        if (call) {
          call.endedAt = now();
          call.isError = event.isError;
        }
        emitUpdate(true);
        break;
      }
    }
  };

  const unsubscribe = session.subscribe(listener);
  return {
    emitUpdate,
    unsubscribe() {
      if (unsubscribed) return;
      unsubscribed = true;
      unsubscribe();
    },
  };
}

/** Attach an abort callback and always return the matching cleanup function. */
export function bindAbortSignal(
  signal: AbortSignal | undefined,
  onAbort: () => void,
): () => void {
  if (!signal) return () => undefined;
  signal.addEventListener("abort", onAbort, { once: true });
  if (signal.aborted) onAbort();
  return () => signal.removeEventListener("abort", onAbort);
}

export interface ActiveSubagentSessionRegistry {
  readonly size: number;
  add(session: DisposableChildSession & Pick<AgentSession, "abort">): () => void;
  shutdown(): Promise<void>;
}

/** Registry used by adapters to clean up all children on parent shutdown. */
export function createActiveSubagentSessionRegistry(): ActiveSubagentSessionRegistry {
  const sessions = new Set<DisposableChildSession & Pick<AgentSession, "abort">>();
  let shutdownPromise: Promise<void> | undefined;
  let shuttingDown = false;
  const lateDisposals = new Set<Promise<void>>();

  const disposeSession = async (
    session: DisposableChildSession & Pick<AgentSession, "abort">,
  ) => {
    try {
      await session.abort();
    } catch {
      // Parent shutdown must continue even if a child rejects abort.
    }
    await shutdownAndDisposeChildSession(session);
  };

  return {
    get size() {
      return sessions.size;
    },
    add(session) {
      let active = true;
      const remove = () => {
        if (!active) return;
        active = false;
        sessions.delete(session);
      };

      // A child can finish creating while the parent is already shutting down.
      // Do not leave that late registration orphaned outside the lifecycle pass.
      if (shuttingDown) {
        const disposal = disposeSession(session);
        lateDisposals.add(disposal);
        void disposal.then(
          () => lateDisposals.delete(disposal),
          () => lateDisposals.delete(disposal),
        );
      } else {
        sessions.add(session);
      }
      return remove;
    },
    async shutdown() {
      if (shutdownPromise) return shutdownPromise;
      shuttingDown = true;
      shutdownPromise = (async () => {
        // Repeat the pass in case a child finishes registering while an earlier
        // child is waiting for its shutdown hook.
        while (sessions.size > 0 || lateDisposals.size > 0) {
          const active = [...sessions];
          sessions.clear();
          await Promise.all([
            ...active.map(disposeSession),
            ...lateDisposals,
          ]);
        }
      })();
      return shutdownPromise;
    },
  };
}

/** Bind extensions and make a failed bind terminal and disposable. */
export async function bindAndPrepareChildSession(
  session: AgentSession,
): Promise<AgentSession> {
  try {
    await bindChildSessionExtensions(session);
  } catch (error) {
    await shutdownAndDisposeChildSession(session);
    throw error;
  }
  return session;
}