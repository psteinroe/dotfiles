// Progress tracking and rendering primitives adapted from default-anton/pi-finder
// and default-anton/pi-librarian (Apache-2.0). See THIRD_PARTY.md.

import { getMarkdownTheme } from "@earendil-works/pi-coding-agent";
import { Container, Markdown, Spacer, Text } from "@earendil-works/pi-tui";

export const MAX_TOOL_CALLS_TO_KEEP = 80;

export type SubagentStatus = "running" | "done" | "error" | "aborted";
export type SubagentTerminationReason =
  | "completed"
  | "cancelled"
  | "turn_limit"
  | "prompt_error"
  | "empty_output"
  | "shutdown";

export interface SubagentToolCall {
  id: string;
  name: string;
  args: unknown;
  startedAt: number;
  endedAt?: number;
  isError?: boolean;
}

/** State shared by adapters while a child is running. */
export interface SubagentRunDetails {
  status: SubagentStatus;
  task: string;
  turns: number;
  /** undefined means that the adapter has no turn limit. */
  maxTurns: number | undefined;
  toolCalls: SubagentToolCall[];
  summaryText?: string;
  error?: string;
  terminationReason?: SubagentTerminationReason;
  startedAt: number;
  endedAt?: number;
}

/** Adapter-facing result metadata. Adapters may use metadata for their own UI. */
export interface SubagentDetails<
  AgentName extends string = string,
  ThinkingLevel extends string = string,
  Metadata = unknown,
> {
  status: SubagentStatus;
  agent?: AgentName;
  taskLabel?: string;
  workspace: string;
  model: string;
  thinking: ThinkingLevel;
  run: SubagentRunDetails;
  metadata?: Metadata;
  tokens?: unknown;
  cost?: number;
  truncated?: boolean;
}

export function shorten(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max)}…`;
}

/** Format known built-in tool arguments without exposing file contents. */
export function formatSubagentToolCall(call: SubagentToolCall): string {
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

export interface SubagentRendererOptions<Details extends SubagentDetails = SubagentDetails> {
  /** Label used in the heading; this can differ from the wire agent name. */
  agentLabel: string | ((details: Details) => string);
  activity: string | ((details: Details) => string);
  formatToolCall?: (call: SubagentToolCall) => string;
  visibleToolCalls?: number;
  collapsedOutputLines?: number;
}

/**
 * Common renderers for delegate-like tools. The returned callbacks can be
 * spread directly into pi.registerTool. Adapters only supply labels/activity.
 */
export function createSubagentRenderers<Details extends SubagentDetails>(
  options: SubagentRendererOptions<Details>,
) {
  const format = options.formatToolCall ?? formatSubagentToolCall;
  const visibleToolCalls = options.visibleToolCalls ?? 6;
  const collapsedOutputLines = options.collapsedOutputLines ?? 18;
  const label = (details: Details) => typeof options.agentLabel === "function"
    ? options.agentLabel(details)
    : options.agentLabel;
  const activity = (details: Details) => typeof options.activity === "function"
    ? options.activity(details)
    : options.activity;

  return {
    renderCall(args: unknown, theme: any) {
      const task = typeof (args as { task?: unknown })?.task === "string"
        ? (args as { task: string }).task.trim()
        : "";
      return new Text(theme.fg("muted", shorten(task.replace(/\s+/g, " "), 70)), 0, 0);
    },

    renderResult(result: any, { expanded, isPartial }: any, theme: any) {
      const details = result.details as Details | undefined;
      if (!details) {
        const content = result.content[0];
        return new Text(content?.type === "text" ? content.text : "(no output)", 0, 0);
      }

      const status = isPartial ? "running" : details.status;
      const icon = status === "done"
        ? theme.fg("success", "✓")
        : status === "error"
          ? theme.fg("error", "✗")
          : status === "aborted"
            ? theme.fg("warning", "◼")
            : theme.fg("warning", "⏳");
      const run = details.run;
      const totalToolCalls = run.toolCalls.length;
      const maxTurns = run.maxTurns === undefined ? "∞" : String(run.maxTurns);
      const header = icon + " "
        + theme.fg("toolTitle", theme.bold(label(details)))
        + theme.fg(
          "dim",
          ` ${details.model}:${details.thinking} • ${run.turns}/${maxTurns} turns • ${totalToolCalls} tool call${totalToolCalls === 1 ? "" : "s"}`,
        );
      const workspaceLine = `${theme.fg("muted", "workspace: ")}${theme.fg("toolOutput", details.workspace)}`;

      let toolsText = "";
      if (run.toolCalls.length > 0) {
        const calls = expanded ? run.toolCalls : run.toolCalls.slice(-visibleToolCalls);
        const lines: string[] = [theme.fg("muted", "Tools:")];
        for (const call of calls) {
          const callIcon = call.isError
            ? theme.fg("error", "✗")
            : call.endedAt
              ? theme.fg("success", "✓")
              : theme.fg("warning", "→");
          lines.push(`${callIcon} ${theme.fg("toolOutput", format(call))}`);
        }
        if (!expanded && run.toolCalls.length > visibleToolCalls) {
          lines.push(theme.fg("muted", "(Ctrl+O to expand)"));
        }
        toolsText = lines.join("\n");
      }

      if (status === "running") {
        let text = `${header}\n${workspaceLine}`;
        if (toolsText) text += `\n\n${toolsText}`;
        text += `\n\n${theme.fg("muted", activity(details))}`;
        return new Text(text, 0, 0);
      }

      const combined = (
        result.content[0]?.type === "text"
          ? result.content[0].text
          : run.summaryText ?? "(no output)"
      ).trim() || "(no output)";

      if (!expanded) {
        const lines = combined.split("\n");
        let text = `${header}\n${workspaceLine}\n\n${theme.fg("toolOutput", lines.slice(0, collapsedOutputLines).join("\n"))}`;
        if (lines.length > collapsedOutputLines) text += `\n${theme.fg("muted", "(Ctrl+O to expand)")}`;
        if (toolsText) text += `\n\n${toolsText}`;
        return new Text(text, 0, 0);
      }

      const container = new Container();
      container.addChild(new Text(header, 0, 0));
      container.addChild(new Text(workspaceLine, 0, 0));
      if (toolsText) {
        container.addChild(new Spacer(1));
        container.addChild(new Text(toolsText, 0, 0));
      }
      container.addChild(new Spacer(1));
      container.addChild(new Markdown(combined, 0, 0, getMarkdownTheme()));
      return container;
    },
  };
}

// Adapter-neutral aliases with names that read well at call sites.
export const formatToolCall = formatSubagentToolCall;
