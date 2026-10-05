import { createHash } from "node:crypto";

export type WatchGoal = "checks" | "ready";
export type PrStatus = "pending" | "waiting_ready" | "passed" | "ready" | "failed" | "conflict" | "head_changed" | "merged" | "closed" | "draft" | "error";
export interface PrTarget { url: string; head: string; key: string }
export interface Check { name: string; state: string; bucket: "pass" | "skipping" | "fail" | "pending"; link: string }
export interface PollState {
  target: PrTarget;
  observedAt: number;
  nextPollAt: number;
  status: PrStatus;
  head: string;
  ready: boolean;
  stablePolls: number;
  fingerprint: string;
  errors: number;
  checks: Check[];
  message?: string;
}

export function targetFor(url: string, head: string): PrTarget {
  const parsed = new URL(url);
  if (parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.search || parsed.hash
    || !/^\/[\w.-]+\/[\w.-]+\/pull\/[1-9]\d*$/.test(parsed.pathname)) throw new Error("Expected an HTTPS pull request URL.");
  if (!/^[a-f0-9]{40,64}$/i.test(head)) throw new Error("GitHub returned an invalid head SHA.");
  const canonical = `${parsed.origin.toLowerCase()}${parsed.pathname.toLowerCase()}`;
  return { url: canonical, head: head.toLowerCase(), key: createHash("sha256").update(`${canonical}@${head.toLowerCase()}`).digest("hex") };
}

function record(value: unknown): Record<string, any> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("GitHub returned malformed PR state.");
  return value as Record<string, any>;
}

export function resolveTarget(value: unknown): PrTarget {
  const pr = record(value);
  if (typeof pr.url !== "string" || typeof pr.headRefOid !== "string") throw new Error("GitHub returned no PR URL/head SHA.");
  return targetFor(pr.url, pr.headRefOid);
}

function normalizeCheck(value: unknown): Check {
  const check = record(value);
  const name = check.name ?? check.context;
  if (typeof name !== "string" || !name) throw new Error("GitHub returned a check without a name.");
  const state = String(check.conclusion || check.status || check.state || "UNKNOWN").toUpperCase();
  const complete = !check.status || check.status === "COMPLETED";
  const bucket = complete && ["SUCCESS", "NEUTRAL"].includes(state) ? "pass"
    : complete && state === "SKIPPED" ? "skipping"
    : complete && ["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STALE", "STARTUP_FAILURE"].includes(state) ? "fail" : "pending";
  return { name: name.slice(0, 160), state, bucket, link: String(check.detailsUrl ?? check.targetUrl ?? "").slice(0, 500) };
}

/** One gh response binds the checks, labels and mergeability to the same head. */
export function advance(target: PrTarget, previous: PollState | undefined, raw: unknown, now: number, intervalMs = 30_000, requiredStablePolls = 3): PollState {
  const pr = record(raw);
  if (!/^[a-f0-9]{40,64}$/i.test(pr.headRefOid ?? "") || !["OPEN", "MERGED", "CLOSED"].includes(pr.state)
    || typeof pr.isDraft !== "boolean" || !Array.isArray(pr.labels)
    || pr.labels.some((label: unknown) => typeof record(label).name !== "string")
    || (pr.statusCheckRollup !== null && !Array.isArray(pr.statusCheckRollup))) throw new Error("GitHub returned incomplete PR state.");
  const head = pr.headRefOid.toLowerCase();
  const checks = (pr.statusCheckRollup ?? []).map(normalizeCheck).sort((a: Check, b: Check) => `${a.name}:${a.link}:${a.state}`.localeCompare(`${b.name}:${b.link}:${b.state}`));
  const ready = pr.labels.some((label: { name: string }) => label.name === "ready");
  const fingerprint = JSON.stringify(checks);
  let status: PrStatus = "pending";
  let stablePolls = 0;
  if (pr.state === "MERGED") status = "merged";
  else if (pr.state === "CLOSED") status = "closed";
  else if (head !== target.head) status = "head_changed";
  else if (pr.isDraft) status = "draft";
  else if (pr.mergeable === "CONFLICTING" || pr.mergeStateStatus === "DIRTY") status = "conflict";
  else if (checks.some((check: Check) => check.bucket === "fail")) status = "failed";
  else if (checks.length && checks.every((check: Check) => check.bucket !== "pending")) {
    stablePolls = previous?.head === head && previous.fingerprint === fingerprint && !previous.errors ? previous.stablePolls + 1 : 1;
    // UNKNOWN mergeability is not evidence of a conflict; automated checks can still settle.
    if (stablePolls >= requiredStablePolls) status = ready ? "ready" : "waiting_ready";
  }
  return { target, observedAt: now, nextPollAt: now + intervalMs, status, head, ready, stablePolls, fingerprint, errors: 0, checks };
}

export function pollError(target: PrTarget, previous: PollState | undefined, error: unknown, now: number, intervalMs = 30_000): PollState {
  const message = (error instanceof Error ? error.message : String(error))
    .replace(/\b(?:Bearer|Basic)\s+\S+/gi, "[redacted]").replace(/\b(?:gh[pousr]_[\w]+|sk-[\w-]+)\b/g, "[redacted]").slice(0, 500);
  const errors = (previous?.errors ?? 0) + 1;
  return { target, observedAt: now, nextPollAt: now + intervalMs, status: errors >= 3 ? "error" : "pending", head: target.head,
    ready: false, stablePolls: 0, fingerprint: "", errors, checks: [], message };
}

export function outcome(state: PollState, goal: WatchGoal): PrStatus | undefined {
  if (state.status === "pending") return;
  if (state.status === "waiting_ready") return goal === "checks" ? "passed" : undefined;
  if (state.status === "ready") return goal === "checks" ? "passed" : "ready";
  return state.status;
}

export function summary(state: PollState): object {
  return { url: state.target.url, expectedHead: state.target.head, head: state.head, status: state.status, ready: state.ready,
    observedAt: new Date(state.observedAt).toISOString(), stablePolls: state.stablePolls,
    passed: state.checks.filter(c => c.bucket === "pass").length, skipped: state.checks.filter(c => c.bucket === "skipping").length,
    pending: state.checks.filter(c => c.bucket === "pending").length,
    failedCount: state.checks.filter(c => c.bucket === "fail").length,
    failed: state.checks.filter(c => c.bucket === "fail").slice(0, 5), ...(state.message ? { message: state.message } : {}) };
}
