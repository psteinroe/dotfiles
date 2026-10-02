export type UsageProvider = "openai-codex" | "claude-bridge";
export interface UsageCredential { access: string; accountId?: string }
export interface UsageWindow { label: string; used: number; resetsAt?: number }
export type UsageState = { windows: UsageWindow[]; fetchedAt: number } | { reason: "sign in" | "unavailable" };

export const USAGE_URLS: Record<UsageProvider, string> = {
  "openai-codex": "https://chatgpt.com/backend-api/wham/usage",
  "claude-bridge": "https://api.anthropic.com/api/oauth/usage",
};

export function bearer(value: unknown): value is string {
  return typeof value === "string" && /^[\x21-\x7e]{1,16384}$/.test(value);
}

function window(label: string, used: unknown, reset: unknown): UsageWindow[] {
  if (typeof used !== "number" || !Number.isFinite(used) || used < 0) return [];
  const resetsAt = typeof reset === "number" && Number.isFinite(reset) && reset > 0 ? reset : undefined;
  return [{ label, used, resetsAt }];
}

export function parseUsage(provider: UsageProvider, body: any): UsageWindow[] {
  if (provider === "claude-bridge") {
    return ([['five_hour', '5h'], ['seven_day', '7d']] as const).flatMap(([key, label]) =>
      window(label, body?.[key]?.utilization, typeof body?.[key]?.resets_at === "string" ? Date.parse(body[key].resets_at) : undefined));
  }
  return [body?.rate_limit?.primary_window, body?.rate_limit?.secondary_window].flatMap((entry) => {
    const seconds = entry?.limit_window_seconds;
    if (typeof seconds !== "number" || !Number.isFinite(seconds) || seconds <= 0) return [];
    const label = seconds >= 86400 ? `${Math.round(seconds / 86400)}d` : seconds >= 3600 ? `${Math.round(seconds / 3600)}h` : `${Math.max(1, Math.round(seconds / 60))}m`;
    return window(label, entry.used_percent, typeof entry.reset_at === "number" ? entry.reset_at * 1000 : undefined);
  });
}

export function abortable<T>(work: Promise<T>, signal: AbortSignal): Promise<T> {
  return new Promise((resolve, reject) => {
    const abort = () => { signal.removeEventListener("abort", abort); reject(new Error("Usage cancelled")); };
    signal.addEventListener("abort", abort, { once: true });
    work.then((value) => { signal.removeEventListener("abort", abort); resolve(value); },
      (error) => { signal.removeEventListener("abort", abort); reject(error); });
    if (signal.aborted) abort();
  });
}

export async function fetchUsage(provider: UsageProvider, credential: UsageCredential, signal: AbortSignal, fetchImpl = fetch, now = Date.now): Promise<UsageState> {
  if (!bearer(credential.access)) return { reason: "sign in" };
  const headers: Record<string, string> = { Authorization: `Bearer ${credential.access}`, Accept: "application/json" };
  if (provider === "openai-codex" && credential.accountId) {
    if (!/^[A-Za-z0-9_-]{1,256}$/.test(credential.accountId)) return { reason: "sign in" };
    headers["ChatGPT-Account-Id"] = credential.accountId;
  }
  if (provider === "claude-bridge") {
    headers["anthropic-beta"] = "oauth-2025-04-20";
    headers["anthropic-version"] = "2023-06-01";
  }
  try {
    signal.throwIfAborted();
    const response = await abortable(fetchImpl(USAGE_URLS[provider], { method: "GET", headers, redirect: "error", signal }), signal);
    if (!response.ok) return { reason: response.status === 401 || response.status === 403 ? "sign in" : "unavailable" };
    const windows = parseUsage(provider, await abortable(response.json(), signal));
    return windows.length ? { windows, fetchedAt: now() } : { reason: "unavailable" };
  } catch { return { reason: "unavailable" }; }
}

export function formatUsage(label: string, state: UsageState | undefined, now = Date.now()): string {
  if (!state) return `${label} …`;
  if ("reason" in state) return `${label} ${state.reason}`;
  const text = state.windows.map((entry) => {
    const left = Math.max(0, Math.min(100, 100 - entry.used));
    const minutes = entry.resetsAt ? Math.ceil((entry.resetsAt - now) / 60000) : 0;
    const reset = minutes > 0 ? ` ↻${minutes >= 60 ? `${Math.floor(minutes / 60)}h${minutes % 60 ? `${minutes % 60}m` : ""}` : `${minutes}m`}` : "";
    return `${entry.label} ${Math.round(left)}% left${reset}`;
  }).join(" · ");
  return `${label} ${text}${now - state.fetchedAt > 300_000 ? " (stale)" : ""}`;
}
