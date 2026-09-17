import type { AgentSession } from "@earendil-works/pi-coding-agent";
import type { Model } from "./subagent-models.ts";
import type { SubagentRunDetails } from "./subagent-progress.ts";

type SubagentSession = Pick<AgentSession, "messages" | "model" | "prompt" | "setModel" | "setThinkingLevel">;
interface FailoverOptions {
  models: Model[];
  thinkingLevel: Parameters<AgentSession["setThinkingLevel"]>[0];
  signal?: AbortSignal;
  run: SubagentRunDetails;
  onModelChange?: (model: Model) => void;
}

const CONTINUATION = "Continue the original task from the existing conversation. The previous provider request failed and the account has changed, but your task, working directory, and completed tool results are unchanged. Do not restart the task or repeat completed tool operations. Inspect current state before retrying any operation whose outcome is uncertain.";

/** Provider error text is diagnostic data, never a reason to expose credentials. */
function safeError(error: unknown): string {
  return (error instanceof Error ? error.message : String(error))
    .replace(/\b(?:Bearer|Basic)\s+\S+/gi, "[redacted authorization]")
    .replace(/((?:api[_-]?key|authorization|cookie|set-cookie)["']?\s*[:=]\s*)[^\r\n]+/gi, "$1[redacted]")
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, "[redacted token]")
    .replace(/\bsk-[A-Za-z0-9_-]+\b/g, "[redacted key]")
    .replace(/((?:access|refresh|id)[_-]?token["']?\s*[:=]\s*["']?)[^\s"',}]+/gi, "$1[redacted]")
    .slice(0, 2000);
}

function isRecoverable(error: string): boolean {
  // Changing accounts cannot fix these failures and must not bypass refusals.
  if (/context.{0,30}(?:exceed|overflow|too (?:long|large))|too many tokens|prompt.{0,20}too (?:long|large)|content[_ ]policy|safety|permission denied|access denied|insufficient permissions/i.test(error)) return false;
  // OAuth token endpoints use 400 for account-specific refresh failures too.
  if (/oauth.{0,40}refresh|refresh_token|invalid_grant/i.test(error)) return true;
  if (/\b400\b/i.test(error)) return false;
  const quotaOrAuth = /unauthori[sz]ed|authentication|no api key found|rate.?limit|quota|usage.?limit/i;
  if (/\b403\b/i.test(error)) return quotaOrAuth.test(error);
  return quotaOrAuth.test(error) || /\b(?:401|402|408|425|429|5\d\d)\b|overloaded|service unavailable|timed? ?out|timeout|econnreset|econnrefused|etimedout|eai_again|fetch failed|network error|socket hang up|model.{0,50}(?:not found|not available|not supported|does not exist)/i.test(error);
}

function checkStopped(options: FailoverOptions): void {
  const { run } = options;
  if (options.signal?.aborted || run.terminationReason === "cancelled" || run.terminationReason === "shutdown") {
    run.terminationReason ??= "cancelled";
    const error = new Error("Subagent was aborted.");
    error.name = "AbortError";
    throw error;
  }
  if (run.terminationReason === "turn_limit" || (run.maxTurns !== undefined && run.turns >= run.maxTurns)) {
    run.terminationReason = "turn_limit";
    throw new Error(`Subagent reached its ${run.maxTurns ?? "configured"}-turn limit; account failover stopped.`);
  }
}

/**
 * Rotate accounts, not role models. Keep one session, tool history and budget;
 * each candidate is attempted at most once and no background retries survive.
 * Callers must use in-memory settings because AgentSession.setModel persists
 * defaults through its SettingsManager even in a headless session.
 */
export async function promptSubagentWithFailover(
  session: SubagentSession,
  prompt: string,
  options: FailoverOptions,
): Promise<void> {
  const { run } = options;
  const models = options.models.filter((model, index, all) =>
    all.findIndex((candidate) => candidate.provider === model.provider) === index);
  if (models.length === 0) throw new Error("No subagent failover candidates are available.");
  if (models.some((model) => model.id !== models[0].id)) {
    throw new Error("Subagent failover must preserve the role model ID.");
  }
  run.attemptedProviders = [];
  run.failoverCount = 0;
  const failures: string[] = [];
  let submitted = false;

  for (const model of models) {
    checkStopped(options);
    run.attemptedProviders.push(model.provider);
    run.failoverCount = run.attemptedProviders.length - 1;
    let failure: string | undefined;
    try {
      if (session.model?.provider !== model.provider || session.model.id !== model.id) {
        await session.setModel(model);
      }
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") run.terminationReason ??= "cancelled";
      failure = safeError(error);
    }
    checkStopped(options);
    if (!failure) {
      session.setThinkingLevel(options.thinkingLevel);
      options.onModelChange?.(model);
      const startIndex = session.messages.length;
      try {
        const nextPrompt = submitted ? CONTINUATION : prompt;
        await session.prompt(nextPrompt, { expandPromptTemplates: false });
      } catch (error) {
        if (error instanceof Error && error.name === "AbortError") run.terminationReason ??= "cancelled";
        failure = safeError(error);
      }
      // A preflight auth rejection may occur before the task enters history.
      submitted ||= session.messages.slice(startIndex).some((message) => message.role === "user");
      // Cancellation wins even if the last request concurrently returned 401.
      if (options.signal?.aborted || run.terminationReason === "cancelled" || run.terminationReason === "shutdown") {
        checkStopped(options);
      }
      const last = session.messages.slice(startIndex).reverse()
        .find((message) => message.role === "assistant");
      if (last?.role === "assistant") {
        if (last.stopReason === "aborted") {
          if (run.terminationReason !== "turn_limit") run.terminationReason = "cancelled";
          checkStopped(options);
        }
        if (last.stopReason === "error") {
          failure = safeError(last.errorMessage || failure || "Provider returned an error without diagnostics.");
          // Pi drops errored assistant messages on replay. Stripping tool calls
          // could orphan results or repeat writes whose outcome is uncertain.
          if (last.content.some((part) => part.type === "toolCall")) {
            throw new Error(`${model.provider}/${model.id}: ${failure} Account failover stopped because the interrupted response contains tool calls; inspect their outcomes before continuing.`);
          }
        }
      }
      if (!failure) return; // Successful empty output is the adapter's concern.
    }
    failures.push(`${model.provider}/${model.id}: ${failure}`);
    checkStopped(options);
    if (!isRecoverable(failure)) throw new Error(failures.join("\n"));
  }
  throw new Error(`Subagent account failover exhausted ${models.length} candidate(s).\n${failures.join("\n")}`);
}
