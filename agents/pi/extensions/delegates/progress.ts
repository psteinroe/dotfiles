// Progress model and tool formatting adapted from default-anton/pi-finder and
// default-anton/pi-librarian (Apache-2.0). See THIRD_PARTY.md.

export const MAX_TOOL_CALLS_TO_KEEP = 80;

export type DelegateStatus = "running" | "done" | "error" | "aborted";

export interface DelegateToolCall {
  id: string;
  name: string;
  args: unknown;
  startedAt: number;
  endedAt?: number;
  isError?: boolean;
}

export interface DelegateRunDetails {
  status: DelegateStatus;
  task: string;
  turns: number;
  maxTurns: number;
  toolCalls: DelegateToolCall[];
  summaryText?: string;
  error?: string;
  startedAt: number;
  endedAt?: number;
}

export interface DelegateDetails {
  status: DelegateStatus;
  delegate: "oracle" | "worker";
  workspace: string;
  model: string;
  thinking: "high" | "xhigh";
  run: DelegateRunDetails;
  tokens?: unknown;
  cost?: number;
  truncated?: boolean;
}

export function shorten(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max)}…`;
}

export function formatToolCall(call: DelegateToolCall): string {
  const args = call.args && typeof call.args === "object"
    ? call.args as Record<string, unknown>
    : undefined;
  const path = typeof args?.path === "string" ? args.path : "";

  if (call.name === "read") {
    const offset = typeof args?.offset === "number" ? args.offset : undefined;
    const limit = typeof args?.limit === "number" ? args.limit : undefined;
    const range = offset || limit
      ? `:${offset ?? 1}${limit ? `-${(offset ?? 1) + limit - 1}` : ""}`
      : "";
    return `read ${path}${range}`.trimEnd();
  }

  if (call.name === "bash") {
    const command = typeof args?.command === "string" ? args.command : "";
    const timeout = typeof args?.timeout === "number" ? args.timeout : undefined;
    const normalized = command.replace(/\s+/g, " ").trim();
    return `bash ${shorten(normalized, 120)}${timeout ? ` (timeout ${timeout}s)` : ""}`.trimEnd();
  }

  if (call.name === "grep") {
    const pattern = typeof args?.pattern === "string" ? args.pattern : "";
    return `grep ${shorten(pattern, 70)}${path ? ` in ${path}` : ""}`;
  }

  if (call.name === "find") {
    const pattern = typeof args?.pattern === "string" ? args.pattern : "";
    return `find ${shorten(pattern, 70)}${path ? ` in ${path}` : ""}`;
  }

  if (call.name === "ls") return `ls ${path || "."}`;
  if (call.name === "git_diff") {
    return `git diff ${typeof args?.target === "string" ? args.target : "working"}`;
  }
  if (call.name === "edit") {
    const edits = Array.isArray(args?.edits) ? args.edits.length : 0;
    return `edit ${path}${edits ? ` (${edits} change${edits === 1 ? "" : "s"})` : ""}`;
  }
  if (call.name === "write") {
    const content = typeof args?.content === "string" ? args.content : "";
    return `write ${path}${content ? ` (${content.length} chars)` : ""}`;
  }

  return call.name;
}
