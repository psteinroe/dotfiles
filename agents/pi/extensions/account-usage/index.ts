import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { abortable, fetchUsage, formatUsage, type UsageCredential, type UsageProvider, type UsageState } from "./core.ts";
import { readUsageCredential } from "./credential-source.ts";

const STATUS_KEY = "account-usage";
const PROVIDERS = ["openai-codex", "claude-bridge"] as const;
const LABELS = { "openai-codex": "Codex", "claude-bridge": "Claude" };
export interface UsageDependencies {
  credential(provider: UsageProvider, ctx: ExtensionContext, signal: AbortSignal): Promise<UsageCredential | undefined>;
  fetch: typeof fetch;
  now(): number;
  intervalMs: number;
  timeoutMs: number;
}

export function createUsageExtension(overrides: Partial<UsageDependencies> = {}) {
  const deps: UsageDependencies = { credential: readUsageCredential, fetch: (...args) => fetch(...args),
    now: Date.now, intervalMs: 120_000, timeoutMs: 8000, ...overrides };
  return (pi: ExtensionAPI) => {
    let current: { ctx: ExtensionContext; lifetime: AbortController; timer?: ReturnType<typeof setInterval>;
      inFlight?: Promise<void>; lastAttempt?: number; states: Partial<Record<UsageProvider, UsageState>> } | undefined;

    function paint(owner: NonNullable<typeof current>) {
      if (current !== owner || owner.lifetime.signal.aborted) return;
      owner.ctx.ui.setStatus(STATUS_KEY, PROVIDERS.map((provider) => formatUsage(LABELS[provider], owner.states[provider], deps.now())).join(" | "));
    }
    function close() {
      const owner = current;
      current = undefined;
      if (!owner) return;
      owner.lifetime.abort();
      clearInterval(owner.timer);
      owner.ctx.ui.setStatus(STATUS_KEY, undefined);
    }
    function refresh(force = false): Promise<void> {
      const owner = current;
      if (!owner) return Promise.resolve();
      if (owner.inFlight) return owner.inFlight;
      if (!force && owner.lastAttempt !== undefined && deps.now() - owner.lastAttempt < deps.intervalMs) {
        paint(owner); return Promise.resolve();
      }
      owner.lastAttempt = deps.now();
      const deadline = new AbortController();
      const timeout = setTimeout(() => deadline.abort(), deps.timeoutMs);
      timeout.unref?.();
      const signal = AbortSignal.any([owner.lifetime.signal, deadline.signal]);
      owner.inFlight = Promise.all(PROVIDERS.map(async (provider) => {
        let state: UsageState;
        try {
          const credential = await abortable(deps.credential(provider, owner.ctx, signal), signal);
          signal.throwIfAborted();
          state = credential ? await fetchUsage(provider, credential, signal, deps.fetch, deps.now) : { reason: "sign in" };
        } catch { state = { reason: "unavailable" }; }
        if (current !== owner || owner.lifetime.signal.aborted) return;
        // Keep the last known windows on a temporary failure; formatUsage marks them stale.
        const previous = owner.states[provider];
        const keepPrevious = "reason" in state && state.reason === "unavailable" && previous && "windows" in previous;
        if (!keepPrevious) owner.states[provider] = state;
        paint(owner);
      })).then(() => {}).finally(() => { clearTimeout(timeout); owner.inFlight = undefined; });
      return owner.inFlight;
    }
    pi.on("session_start", (_event, ctx) => {
      close();
      if (ctx.mode !== "tui") return;
      current = { ctx, lifetime: new AbortController(), states: {} };
      paint(current);
      current.timer = setInterval(() => { void refresh(); }, deps.intervalMs);
      current.timer.unref?.();
      void refresh();
    });
    pi.on("session_shutdown", () => close());
    pi.on("agent_end", () => { void refresh(); });
    pi.on("model_select", () => { void refresh(); });
    pi.registerCommand("account-usage", {
      description: "Refresh subscription quota status for Codex and Claude Code",
      handler: async (_args, ctx) => {
        if (ctx.mode !== "tui") { ctx.ui.notify("Account usage is available in interactive mode.", "info"); return; }
        await refresh(true);
      },
    });
  };
}

export default createUsageExtension();
