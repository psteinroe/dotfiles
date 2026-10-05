import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { advance, outcome, pollError, resolveTarget, summary, type PollState, type PrStatus, type PrTarget, type WatchGoal } from "./state.ts";
import { SharedStore } from "./store.ts";

const exec = promisify(execFile);
export async function ghJson(args: string[], cwd: string, signal?: AbortSignal): Promise<unknown> {
  const { stdout } = await exec("gh", args, { cwd, signal, timeout: 20_000, maxBuffer: 2 * 1024 * 1024, encoding: "utf8" });
  return JSON.parse(stdout);
}
export const POLL_FIELDS = "url,headRefOid,state,isDraft,labels,mergeable,mergeStateStatus,statusCheckRollup";
export interface WatchSnapshot {
  id: string; target: PrTarget; goal: WatchGoal; createdAt: number; deadline: number;
  status: PrStatus | "watching" | "timeout" | "cancelled";
  state?: PollState;
}
interface Subscription { snapshot: WatchSnapshot; cwd: string; waitingNotified: boolean }
export interface ManagerOptions {
  now?: () => number;
  poll?: (target: PrTarget, cwd: string, signal: AbortSignal) => Promise<unknown>;
  intervalMs?: number;
  notify: (watch: WatchSnapshot, terminal: boolean) => void;
}

export class PrMonitor {
  private readonly subscriptions = new Map<string, Subscription>();
  private readonly controllers = new Map<string, AbortController>();
  private counter = 0;
  private closed = false;
  private ticking = false;
  private timer?: ReturnType<typeof setInterval>;
  private readonly now: () => number;
  private readonly interval: number;
  readonly store: SharedStore;
  private readonly options: ManagerOptions;
  constructor(store: SharedStore, options: ManagerOptions) {
    this.store = store;
    this.options = options;
    this.now = options.now ?? Date.now;
    this.interval = options.intervalMs ?? 30_000;
  }
  async resolve(selector: string, repo: string | undefined, cwd: string, signal?: AbortSignal): Promise<PrTarget> {
    if (!/^[1-9]\d*$/.test(selector) && !/^https:\/\/[^/]+\/[\w.-]+\/[\w.-]+\/pull\/[1-9]\d*$/.test(selector)) throw new Error("pr must be a PR number or HTTPS PR URL.");
    if (repo && !/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error("repo must be owner/repo.");
    return resolveTarget(await ghJson(["pr", "view", selector, ...(repo ? ["--repo", repo] : []), "--json", "url,headRefOid"], cwd, signal));
  }
  watch(target: PrTarget, goal: WatchGoal, cwd: string, timeoutSeconds: number): WatchSnapshot {
    if (this.closed) throw new Error("PR monitoring is shut down.");
    if (!Number.isSafeInteger(timeoutSeconds) || timeoutSeconds < 1 || timeoutSeconds > 604_800) throw new Error("timeout_seconds must be between 1 and 604800.");
    const existing = [...this.subscriptions.values()].find(s => s.snapshot.target.key === target.key && s.snapshot.goal === goal && s.snapshot.status === "watching");
    if (existing) return structuredClone(existing.snapshot);
    // Bound session history; never discard live subscriptions.
    if (this.subscriptions.size >= 64) {
      for (const [id, subscription] of this.subscriptions) {
        if (subscription.snapshot.status !== "watching") this.subscriptions.delete(id);
        if (this.subscriptions.size < 64) break;
      }
      if (this.subscriptions.size >= 64) throw new Error("At most 64 PR subscriptions can be active in one session.");
    }
    const now = this.now();
    const snapshot: WatchSnapshot = { id: `pr-watch-${++this.counter}`, target, goal, createdAt: now, deadline: now + timeoutSeconds * 1000, status: "watching" };
    this.subscriptions.set(snapshot.id, { snapshot, cwd, waitingNotified: false });
    return structuredClone(snapshot);
  }
  list(): WatchSnapshot[] { return [...this.subscriptions.values()].map(s => structuredClone(s.snapshot)); }
  get(id: string): WatchSnapshot {
    const subscription = this.subscriptions.get(id);
    if (!subscription) throw new Error(`Unknown PR subscription ${id}. Use pr_watch_status to list subscriptions.`);
    return structuredClone(subscription.snapshot);
  }
  cancel(id: string): WatchSnapshot {
    const subscription = this.subscriptions.get(id);
    if (!subscription) return this.get(id);
    if (subscription.snapshot.status === "watching") subscription.snapshot.status = "cancelled";
    // This only removes the caller's interest, never another Pi process's poller/subscription.
    return structuredClone(subscription.snapshot);
  }
  start(): void {
    if (this.timer || this.closed) return;
    this.timer = setInterval(() => { void this.tick().catch(() => undefined); }, 2_000);
    this.timer.unref?.();
  }
  private async sample(target: PrTarget, cwd: string): Promise<PollState | undefined> {
    let state = this.store.read(target.key);
    if (state && state.nextPollAt > this.now()) return state;
    const release = this.store.acquire(target.key);
    if (!release) return this.store.read(target.key);
    const controller = new AbortController();
    this.controllers.set(target.key, controller);
    try {
      // Another process may have completed a poll between the initial read and lock acquisition.
      state = this.store.read(target.key);
      if (state && state.nextPollAt > this.now()) return state;
      let next: PollState;
      try {
        const raw = await (this.options.poll?.(target, cwd, controller.signal)
          ?? ghJson(["pr", "view", target.url, "--json", POLL_FIELDS], cwd, controller.signal));
        if (this.closed) return;
        next = advance(target, state, raw, this.now(), this.interval);
      } catch (error) {
        if (this.closed) return;
        next = pollError(target, state, error, this.now(), this.interval);
      }
      this.store.write(target.key, next);
      return next;
    } finally { this.controllers.delete(target.key); release(); }
  }
  async tick(): Promise<void> {
    if (this.closed || this.ticking) return;
    this.ticking = true;
    try {
      const groups = new Map<string, Subscription[]>();
      for (const subscription of this.subscriptions.values()) {
        if (subscription.snapshot.status !== "watching") continue;
        if (this.now() >= subscription.snapshot.deadline) {
          subscription.snapshot.status = "timeout";
          this.options.notify(structuredClone(subscription.snapshot), true);
          continue;
        }
        const key = subscription.snapshot.target.key;
        groups.set(key, [...(groups.get(key) ?? []), subscription]);
      }
      // Different PRs are independent; per-key filesystem locks serialize all processes.
      const pollGroups = [...groups.values()];
      for (let offset = 0; offset < pollGroups.length && !this.closed; offset += 4) {
        await Promise.all(pollGroups.slice(offset, offset + 4).map(async subscriptions => {
          const first = subscriptions[0];
          let state: PollState | undefined;
          try { state = await this.sample(first.snapshot.target, first.cwd); }
          catch (error) { state = pollError(first.snapshot.target, first.snapshot.state, error, this.now(), this.interval); }
          if (!state || this.closed) return;
          for (const subscription of subscriptions) {
            const watch = subscription.snapshot;
            if (watch.status !== "watching") continue;
            if (this.now() >= watch.deadline) {
              watch.status = "timeout";
              this.options.notify(structuredClone(watch), true);
              continue;
            }
            if (state.observedAt < watch.createdAt) continue;
            watch.state = state;
            const terminal = outcome(state, watch.goal);
            if (terminal) {
              watch.status = terminal;
              this.options.notify(structuredClone(watch), true);
            } else if (state.status === "waiting_ready" && !subscription.waitingNotified) {
              subscription.waitingNotified = true;
              this.options.notify(structuredClone(watch), false);
            }
          }
        }));
      }
    } finally { this.ticking = false; }
  }
  shutdown(): void {
    this.closed = true;
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
    for (const controller of this.controllers.values()) controller.abort();
    for (const subscription of this.subscriptions.values()) if (subscription.snapshot.status === "watching") subscription.snapshot.status = "cancelled";
  }
}

export function watchSummary(watch: WatchSnapshot): object {
  return { id: watch.id, status: watch.status, until: watch.goal, url: watch.target.url, expectedHead: watch.target.head,
    ...(watch.state ? { result: summary(watch.state) } : {}) };
}
