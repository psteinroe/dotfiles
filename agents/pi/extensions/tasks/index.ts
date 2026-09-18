import * as path from "node:path";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import installDelegates from "../delegates/adapter.ts";
import installFinder from "../finder/adapter.ts";
import installLibrarian from "../librarian/adapter.ts";
import {
  formatBytes,
  formatElapsed,
  MAX_RUNNING,
  tail,
  TerminalManager,
  type TerminalSnapshot,
} from "../background-terminals/src/manager.ts";
import { HerdrBackgroundMetadata } from "../background-terminals/src/herdr-metadata.ts";
import { TaskDelivery } from "./delivery.ts";
import {
  TaskRegistry,
  type TaskSnapshot,
  type TaskStatus,
} from "./registry.ts";

const RESULT_MESSAGE_TYPE = "background-task-result";
const UI_KEY = "background-tasks";
const RESULT_STDOUT_MAX = 8 * 1024;
const RESULT_STDERR_MAX = 4 * 1024;

const SUBAGENT_NAMES = ["finder", "librarian", "oracle", "worker"] as const;
type SubagentName = typeof SUBAGENT_NAMES[number];
const SUBAGENT_CAPACITY: Record<SubagentName, number> = {
  finder: 4,
  librarian: 2,
  oracle: 1,
  worker: 4,
};

type ToolDefinition = {
  name: string;
  execute: (
    id: string,
    params: any,
    signal: AbortSignal | undefined,
    onUpdate: ((result: any) => void) | undefined,
    ctx: ExtensionContext,
  ) => Promise<any> | any;
};

type EventHandler = (event: any, ctx: ExtensionContext) => unknown;

function glyph(status: TaskStatus): string {
  switch (status) {
    case "starting": return "◌";
    case "running": return "●";
    case "cancelling": return "◐";
    case "done": return "✓";
    case "cancelled": return "⊘";
    case "failed": return "✗";
  }
}

function taskLine(task: TaskSnapshot): string {
  const age = formatElapsed(task.createdAt, task.settledAt);
  const role = task.agent ? ` ${task.agent}` : " command";
  return `${glyph(task.status)} ${task.id} [${task.status}]${role} "${task.title}" ${age}`;
}

function contentText(result: any): string {
  return Array.isArray(result?.content)
    ? result.content
      .filter((part: any) => part?.type === "text" && typeof part.text === "string")
      .map((part: any) => part.text)
      .join("\n")
      .trim()
    : "";
}

function boundedText(text: string, maxChars = 32_000, maxLines = 400): string {
  const lines = text.split("\n");
  let output = lines.length > maxLines ? lines.slice(0, maxLines).join("\n") : text;
  if (output.length > maxChars) output = output.slice(0, maxChars);
  return output === text ? output : `${output}\n\n[task output truncated]`;
}

function boundedValue(value: unknown, maxChars = 2_000): unknown {
  if (value === undefined || value === null) return value;
  if (typeof value === "string") return boundedText(value, maxChars, 80);
  try {
    const serialized = JSON.stringify(value);
    return serialized.length <= maxChars ? value : `${serialized.slice(0, maxChars)}…`;
  } catch {
    return "[unserializable]";
  }
}

function sanitizeDetails(details: any): unknown {
  if (!details || typeof details !== "object") return boundedValue(details);
  const run = details.run && typeof details.run === "object"
    ? {
        ...details.run,
        task: boundedValue(details.run.task, 4_000),
        summaryText: boundedValue(details.run.summaryText, 8_000),
        error: boundedValue(details.run.error, 4_000),
        toolCalls: Array.isArray(details.run.toolCalls)
          ? details.run.toolCalls.slice(-12).map((call: any) => ({
              ...call,
              args: boundedValue(call?.args),
            }))
          : [],
      }
    : undefined;
  return {
    ...details,
    ...(run ? { run } : {}),
  };
}

function progressText(result: any): string | undefined {
  const text = contentText(result);
  return text ? boundedText(text, 8_000, 120) : undefined;
}

function subagentParams(
  agent: SubagentName,
  params: {
    task: string;
    repos?: string[];
    owners?: string[];
    max_search_results?: number;
    write_scope?: string[];
  },
) {
  if (agent === "finder") return { query: params.task };
  if (agent === "librarian") {
    return {
      query: params.task,
      ...(params.repos ? { repos: params.repos } : {}),
      ...(params.owners ? { owners: params.owners } : {}),
      ...(params.max_search_results !== undefined
        ? { maxSearchResults: params.max_search_results }
        : {}),
    };
  }
  if (agent === "worker" && params.write_scope?.length) {
    return {
      task: [
        params.task,
        "",
        "Declared write scope for this task:",
        ...params.write_scope.map((entry) => `- ${entry}`),
        "Structured edit/write calls are blocked outside this scope. Shell commands must also keep their writes inside it. The coordinator may continue read-only work while you run.",
      ].join("\n"),
      writeScope: params.write_scope,
    };
  }
  return { task: params.task };
}

function section(
  label: string,
  view: TerminalSnapshot["stdout"],
  maxBytes: number,
  maxLines: number,
  omitEmpty = false,
): string | undefined {
  if (!view.text) return omitEmpty ? undefined : `${label}: (empty)`;
  const result = tail(view.text, maxBytes, maxLines);
  const note = result.truncated || view.truncatedBytes > 0
    ? ` [truncated: showing the last ${formatBytes(Buffer.byteLength(result.text, "utf8"))} of ${formatBytes(view.totalBytes)}]`
    : "";
  return `${label}${note}:\n${result.text}`;
}

function commandResult(snapshot: TerminalSnapshot): string {
  return [
    `Background command ${snapshot.status}`
      + (snapshot.exitCode !== undefined && snapshot.exitCode !== null ? ` (exit ${snapshot.exitCode})` : "")
      + (snapshot.signal ? ` (signal ${snapshot.signal})` : ""),
    `command: ${snapshot.command}`,
    snapshot.errorText ? `error: ${snapshot.errorText}` : undefined,
    section("stdout", snapshot.stdout, RESULT_STDOUT_MAX, 40),
    section("stderr", snapshot.stderr, RESULT_STDERR_MAX, 20, true),
  ].filter(Boolean).join("\n");
}

function safeJson(value: unknown): string {
  try {
    const serialized = JSON.stringify(value, null, 2);
    return boundedText(serialized ?? String(value), 12_000, 240);
  } catch {
    return "[unserializable details]";
  }
}

function taskDetail(task: TaskSnapshot, expanded = false): string {
  const progress = task.details as any;
  const run = progress?.run;
  return [
    taskLine(task),
    `cwd: ${task.cwd}`,
    task.command ? `command: ${task.command}` : undefined,
    task.writeScope?.length ? `write scope: ${task.writeScope.join(", ")}` : undefined,
    run ? `turns: ${run.turns}${run.maxTurns === undefined ? "" : `/${run.maxTurns}`}` : undefined,
    run?.toolCalls?.length
      ? `recent tools: ${run.toolCalls.slice(-5).map((call: any) => call.name).join(", ")}`
      : undefined,
    task.errorText ? `error: ${task.errorText}` : undefined,
    task.resultText ? `\n${task.resultText}` : undefined,
    expanded && task.details !== undefined ? `\ndetails:\n${safeJson(task.details)}` : undefined,
  ].filter(Boolean).join("\n");
}

function collectSubagentTools(pi: ExtensionAPI) {
  const tools = new Map<string, ToolDefinition>();
  const shutdownHandlers: EventHandler[] = [];
  const scopedPi = new Proxy(pi as any, {
    get(target, property) {
      if (property === "registerTool") {
        return (definition: ToolDefinition) => tools.set(definition.name, definition);
      }
      if (property === "registerCommand") return () => undefined;
      if (property === "on") {
        return (event: string, handler: EventHandler) => {
          if (event === "session_shutdown") shutdownHandlers.push(handler);
          else target.on(event, handler);
        };
      }
      const value = target[property];
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) as ExtensionAPI;

  installFinder(scopedPi);
  installLibrarian(scopedPi);
  installDelegates(scopedPi);

  for (const name of SUBAGENT_NAMES) {
    if (!tools.has(name)) throw new Error(`Subagent adapter did not register ${name}`);
  }
  return { tools, shutdownHandlers };
}

export default function tasksExtension(pi: ExtensionAPI) {
  const registry = new TaskRegistry();
  const terminalManager = new TerminalManager();
  const terminalTaskIds = new Map<string, string>();
  const herdrMetadata = new HerdrBackgroundMetadata();
  const subagents = collectSubagentTools(pi);
  let uiCtx: ExtensionContext | undefined;
  let ownsHerdrMetadata = false;
  let shuttingDown = false;

  const delivery = new TaskDelivery(
    async (tasks) => {
      await pi.sendMessage(
        {
          customType: RESULT_MESSAGE_TYPE,
          content: boundedText(
            tasks.map((task) => taskDetail({
              ...task,
              resultText: task.resultText ? boundedText(task.resultText, 4_000, 100) : undefined,
            })).join("\n\n---\n\n"),
            40_000,
            800,
          ),
          display: true,
          details: {
            tasks: tasks.map((task) => ({
              id: task.id,
              kind: task.kind,
              title: task.title,
              status: task.status,
              agent: task.agent,
            })),
          },
        },
        { deliverAs: "followUp", triggerTurn: true },
      );
      for (const task of tasks) registry.consume(task.id);
    },
    { canDeliver: () => Boolean(uiCtx?.isIdle() && !uiCtx.hasPendingMessages()) },
  );

  const activeTasks = () => registry.list().filter((task) =>
    task.status === "starting" || task.status === "running" || task.status === "cancelling");
  const activeBackgroundCommand = () => activeTasks().find((task) => task.kind === "command");
  const refreshHerdrMetadata = () => {
    if (!ownsHerdrMetadata || shuttingDown) return;
    void herdrMetadata.setActive(activeTasks().length > 0);
  };
  const refreshUi = () => {
    if (!uiCtx?.hasUI) return;
    const active = activeTasks();
    uiCtx.ui.setStatus(
      UI_KEY,
      active.length
        ? uiCtx.ui.theme.fg("warning", `● ${active.length} background task${active.length === 1 ? "" : "s"} · /tasks`)
        : undefined,
    );
    uiCtx.ui.setWidget(UI_KEY, active.length ? active.map(taskLine) : undefined);
  };

  registry.onSettle((snapshot, consumed) => {
    refreshUi();
    refreshHerdrMetadata();
    if (uiCtx?.isIdle()) delivery.setIdle();
    else delivery.setBusy();
    if (consumed) delivery.consume(snapshot.id);
    else delivery.enqueue(snapshot);
  });

  const currentTask = (id: string): TaskSnapshot | undefined => {
    const task = registry.get(id);
    if (!task || task.kind !== "command" || !task.backendId) return task;
    if (task.status !== "starting" && task.status !== "running" && task.status !== "cancelling") return task;
    const terminal = terminalManager.get(task.backendId);
    if (!terminal) return task;
    return {
      ...task,
      resultText: commandResult(terminal),
      details: {
        pid: terminal.pid ?? null,
        backendStatus: terminal.status,
        exitCode: terminal.exitCode ?? null,
        signal: terminal.signal ?? null,
        stdoutBytes: terminal.stdout.totalBytes,
        stderrBytes: terminal.stderr.totalBytes,
      },
    };
  };

  terminalManager.onSettle((snapshot) => {
    const taskId = terminalTaskIds.get(snapshot.id);
    if (!taskId) return;
    terminalTaskIds.delete(snapshot.id);
    const status = snapshot.status === "done"
      ? "done"
      : snapshot.status === "killed" ? "cancelled" : "failed";
    registry.settle(taskId, status, {
      resultText: commandResult(snapshot),
      errorText: snapshot.errorText,
      details: {
        pid: snapshot.pid ?? null,
        backendStatus: snapshot.status,
        exitCode: snapshot.exitCode ?? null,
        signal: snapshot.signal ?? null,
        stdoutBytes: snapshot.stdout.totalBytes,
        stderrBytes: snapshot.stderr.totalBytes,
      },
    });
  });

  pi.on("session_start", async (_event, ctx) => {
    uiCtx = ctx;
    ownsHerdrMetadata = ctx.mode === "tui";
    if (ctx.isIdle()) delivery.setIdle();
    else delivery.setBusy();
    refreshUi();
    refreshHerdrMetadata();
  });
  pi.on("agent_start", async () => delivery.setBusy());
  pi.on("agent_settled", async (_event, ctx) => {
    if (ctx.isIdle()) delivery.setIdle();
    else delivery.setBusy();
  });

  // Keep the coordinator read-only around live Worker mutations. Worker shell
  // writes remain policy-constrained because arbitrary shell effects cannot be
  // proven from command text.
  pi.on("tool_call", (event) => {
    const activeWorker = registry.firstActiveWorker();
    if (!activeWorker) return;
    if (isToolCallEventType("bash", event)) {
      return {
        block: true,
        reason: `${activeWorker.id} (${activeWorker.title}) is editing in the background. Use read-only tools or cancel the Worker before running coordinator shell commands.`,
      };
    }
    if (!isToolCallEventType("edit", event) && !isToolCallEventType("write", event)) return;
    const rawPath = (event.input as { path?: unknown }).path;
    if (typeof rawPath !== "string" || !rawPath.trim()) {
      return { block: true, reason: "File mutation requires a valid path." };
    }
    const absolute = path.resolve(uiCtx?.cwd ?? process.cwd(), rawPath.replace(/^@/, ""));
    const owner = registry.conflictsWithActiveWorker(absolute);
    if (owner) {
      return {
        block: true,
        reason: `${owner.id} (${owner.title}) owns this write scope until it settles. Continue read-only work or cancel the task first.`,
      };
    }
  });

  pi.on("session_shutdown", async (event, ctx) => {
    delivery.shutdown();
    shuttingDown = true;
    uiCtx?.ui.setStatus(UI_KEY, undefined);
    uiCtx?.ui.setWidget(UI_KEY, undefined);
    uiCtx = undefined;
    // Registry cancellation owns the first teardown request. The terminal pass
    // is a bounded safety net after command cancellation has settled.
    await registry.shutdown();
    await terminalManager.disposeAll();
    terminalTaskIds.clear();
    await Promise.allSettled([
      ...subagents.shutdownHandlers.map((handler) => Promise.resolve(handler(event, ctx))),
      ownsHerdrMetadata ? herdrMetadata.shutdown() : Promise.resolve(),
    ]);
  });

  pi.registerTool({
    name: "start_subagent",
    label: "Start Subagent",
    description:
      "Start Finder, Librarian, Oracle, or Worker as a session-scoped background task and return immediately. Finder scouts the local workspace; Librarian researches GitHub; Oracle gives a read-only architecture/debugging second opinion; Worker implements a bounded change. The delegated scope is owned by that subagent until it settles. All profiles receive the configured Executor MCP tools. Completion is delivered automatically.",
    promptSnippet: "Delegate bounded work with an explicit ownership transfer",
    promptGuidelines: [
      "Use start_subagent for delegated research, review, or implementation. Partition work into bounded, non-overlapping scopes before launching.",
      "Once accepted, the delegated scope is owned by that subagent until it settles. Continue only with clearly disjoint work; if none remains, end the turn and let automatic completion resume it.",
      "Reserve the final answer until every required delegated result is integrated. While required work is active, end the turn without an interim conclusion.",
      "Review and integrate the delegated result before doing any remaining work in its scope. Use task_status only when progress is needed to unblock disjoint current work.",
      "For Finder, Librarian, and Oracle, express semantic ownership boundaries in the task text; write_scope is Worker-only. For Worker tasks, provide a narrow write_scope with no overlap with the coordinator or another Worker.",
    ],
    executionMode: "parallel",
    parameters: Type.Object({
      agent: StringEnum(SUBAGENT_NAMES, {
        description: "Subagent profile to run in the background.",
      }),
      task: Type.String({ description: "Self-contained task, constraints, relevant paths, and expected result." }),
      repos: Type.Optional(Type.Array(Type.String(), { maxItems: 30, description: "Librarian owner/repo filters." })),
      owners: Type.Optional(Type.Array(Type.String(), { maxItems: 30, description: "Librarian owner/org filters." })),
      max_search_results: Type.Optional(Type.Integer({ minimum: 1, maximum: 100 })),
      write_scope: Type.Optional(Type.Array(Type.String(), {
        minItems: 1,
        description: "Worker-only files or directory prefixes exclusively owned while the task runs.",
      })),
    }, { additionalProperties: false }),
    async execute(_toolCallId, params: any, signal, _onUpdate, ctx) {
      if (signal?.aborted) throw new Error("Subagent launch was cancelled before acceptance.");
      const agent = params.agent as SubagentName;
      const taskText = typeof params.task === "string" ? params.task.trim() : "";
      if (!taskText) throw new Error("task must not be empty");
      const hasLibrarianFields = params.repos !== undefined
        || params.owners !== undefined
        || params.max_search_results !== undefined;
      if (agent !== "librarian" && hasLibrarianFields) {
        throw new Error("repos, owners, and max_search_results apply only to Librarian tasks.");
      }
      if (agent !== "worker" && params.write_scope !== undefined) {
        throw new Error("write_scope applies only to Worker tasks.");
      }
      if (agent === "worker" && (!Array.isArray(params.write_scope) || params.write_scope.length === 0)) {
        throw new Error("Worker tasks require a non-empty write_scope so background edits cannot overlap.");
      }
      if (agent === "worker") {
        const command = activeBackgroundCommand();
        if (command) {
          throw new Error(
            `Cannot start Worker while background command ${command.id} (${command.title}) is active.`,
          );
        }
      }
      const activeForProfile = activeTasks().filter((task) => task.agent === agent).length;
      if (activeForProfile >= SUBAGENT_CAPACITY[agent]) {
        throw new Error(
          `At most ${SUBAGENT_CAPACITY[agent]} ${agent} task${SUBAGENT_CAPACITY[agent] === 1 ? "" : "s"} can run concurrently.`,
        );
      }
      const normalizedScope = agent === "worker"
        ? registry.assertWriteScopeAvailable(ctx.cwd, params.write_scope)
        : undefined;
      const controller = new AbortController();
      const title = `${agent}: ${taskText.replace(/\s+/g, " ").slice(0, 72)}`;
      const task = registry.create({
        kind: "subagent",
        title,
        cwd: ctx.cwd,
        status: "starting",
        agent,
        ...(normalizedScope ? { writeScope: normalizedScope } : {}),
        cancel: () => controller.abort(),
      });
      refreshUi();
      refreshHerdrMetadata();

      const definition = subagents.tools.get(agent)!;
      const run = Promise.resolve().then(() => definition.execute(
        task.id,
        subagentParams(agent, {
          task: taskText,
          repos: params.repos,
          owners: params.owners,
          max_search_results: params.max_search_results,
          write_scope: normalizedScope,
        }),
        controller.signal,
        (update) => {
          registry.update(task.id, {
            status: "running",
            resultText: progressText(update),
            details: sanitizeDetails(update?.details),
          });
          refreshUi();
        },
        ctx,
      ));

      void run.then((result) => {
        const detailsStatus = result?.details?.status;
        const text = boundedText(contentText(result) || `${agent} completed without text output.`);
        const status = detailsStatus === "aborted" || controller.signal.aborted
          ? "cancelled"
          : result?.isError || detailsStatus === "error" ? "failed" : "done";
        registry.settle(task.id, status, {
          resultText: text,
          errorText: status === "failed" ? text : undefined,
          details: sanitizeDetails(result?.details),
        });
      }).catch((error) => {
        const message = boundedText(error instanceof Error ? error.message : String(error), 8_000, 120);
        registry.settle(task.id, controller.signal.aborted ? "cancelled" : "failed", {
          resultText: controller.signal.aborted ? "Cancelled" : message,
          errorText: controller.signal.aborted ? undefined : message,
        });
      });

      return {
        content: [{
          type: "text" as const,
          text: `Started ${task.id} "${title}". Its scope is now owned by the ${agent} until it settles. Continue only with disjoint work. If required work remains, reserve the final answer and end the turn; completion will resume it automatically.`,
        }],
        details: task,
      };
    },
  });

  pi.registerTool({
    name: "start_background_command",
    label: "Start Background Command",
    description:
      "Start a long-running shell command as a session-scoped background task and return immediately. Commands use Bash on macOS/Linux and ComSpec on Windows, receive no stdin, and are terminated with the Pi session. Use regular bash for commands that finish in seconds. Completion is delivered automatically; do not poll or sleep while waiting.",
    promptSnippet: "Start a long-running command without blocking the coordinator",
    promptGuidelines: [
      "Use start_background_command for dev servers, watchers, log tails, streaming builds, and long test suites; use bash for commands that finish quickly.",
      "After start_background_command returns, continue useful work or end the turn. Do not poll task_status or run foreground sleep while waiting; completion resumes the agent automatically.",
    ],
    executionMode: "parallel",
    parameters: Type.Object({
      command: Type.String(),
      title: Type.String({ description: "Short recognizable label." }),
      working_dir: Type.Optional(Type.String({ description: "Directory relative to the session cwd." })),
    }, { additionalProperties: false }),
    async execute(_toolCallId, params: any, signal, _onUpdate, ctx) {
      if (signal?.aborted) throw new Error("Background command launch was cancelled before acceptance.");
      const worker = registry.firstActiveWorker();
      if (worker) {
        throw new Error(
          `Cannot start background command while Worker ${worker.id} (${worker.title}) is active.`,
        );
      }
      const cwd = path.resolve(ctx.cwd, params.working_dir ?? ".");
      const terminal = terminalManager.start({ command: params.command, title: params.title, cwd });
      let task: TaskSnapshot;
      try {
        task = registry.create({
          kind: "command",
          title: terminal.title,
          cwd,
          status: "running",
          command: terminal.command,
          backendId: terminal.id,
          cancel: () => terminalManager.kill(terminal.id).then(() => undefined),
        });
      } catch (error) {
        void terminalManager.kill(terminal.id).catch(() => undefined);
        throw error;
      }
      terminalTaskIds.set(terminal.id, task.id);
      refreshUi();
      refreshHerdrMetadata();
      return {
        content: [{
          type: "text" as const,
          text: `Started ${task.id} "${task.title}"${terminal.pid ? ` (pid ${terminal.pid})` : ""}. Continue useful work; do not poll. Completion will be delivered automatically.`,
        }],
        details: task,
      };
    },
  });

  pi.registerTool({
    name: "task_status",
    label: "Task Status",
    description:
      "Show current progress for one background task. Use only when the details are needed to unblock immediate work, not for polling. This does not consume a completed result.",
    parameters: Type.Object({ id: Type.String() }, { additionalProperties: false }),
    async execute(_id, params: any) {
      const task = currentTask(params.id);
      if (!task) throw new Error(`No task ${params.id}. Use task_list to see known tasks.`);
      return { content: [{ type: "text" as const, text: taskDetail(task, true) }], details: task };
    },
  });

  pi.registerTool({
    name: "task_result",
    label: "Task Result",
    description:
      "Collect a completed background task result. If the task is still active, returns its current status immediately and never waits. Collecting a settled result suppresses duplicate automatic delivery.",
    parameters: Type.Object({ id: Type.String() }, { additionalProperties: false }),
    async execute(_id, params: any) {
      const task = currentTask(params.id);
      if (!task) throw new Error(`No task ${params.id}. Use task_list to see known tasks.`);
      const settled = task.status === "done" || task.status === "failed" || task.status === "cancelled";
      if (settled) {
        registry.consume(task.id);
        delivery.consume(task.id);
      }
      return { content: [{ type: "text" as const, text: taskDetail(task, true) }], details: task };
    },
  });

  pi.registerTool({
    name: "task_list",
    label: "List Tasks",
    description: "List session-scoped background commands and subagents with their status and age.",
    parameters: Type.Object({}, { additionalProperties: false }),
    async execute() {
      const tasks = registry.list();
      return {
        content: [{
          type: "text" as const,
          text: tasks.length ? tasks.map(taskLine).join("\n") : "No background tasks.",
        }],
        details: { count: tasks.length, active: activeTasks().length },
      };
    },
  });

  pi.registerTool({
    name: "task_cancel",
    label: "Cancel Tasks",
    description:
      "Request cancellation of one or more background tasks and return immediately. Use for a user request, invalid or unsafe scope, a stuck task, or a requirements change. Coordinator duplication is not a cancellation reason. Subagents are aborted; command process trees receive SIGTERM and escalate to SIGKILL if needed.",
    parameters: Type.Object({ ids: Type.Array(Type.String(), { minItems: 1 }) }, { additionalProperties: false }),
    async execute(_id, params: any) {
      const lines: string[] = [];
      for (const id of params.ids) {
        try {
          registry.consume(id);
          delivery.consume(id);
          const task = registry.cancel(id);
          lines.push(`${task.id} ${task.status}`);
        } catch (error) {
          lines.push(`${id}: ${error instanceof Error ? error.message : String(error)}`);
        }
      }
      refreshUi();
      return { content: [{ type: "text" as const, text: lines.join("\n") }], details: { count: params.ids.length } };
    },
  });

  pi.registerCommand("tasks", {
    description: "List background tasks; '/tasks cancel <id>' cancels one",
    handler: async (args, ctx) => {
      const argv = args.trim().split(/\s+/).filter(Boolean);
      if (argv[0] === "cancel" && argv[1]) {
        registry.consume(argv[1]);
        delivery.consume(argv[1]);
        const task = registry.cancel(argv[1]);
        ctx.ui.notify(`${task.id} ${task.status}`, "info");
        return;
      }
      const tasks = registry.list();
      ctx.ui.notify(tasks.length ? tasks.map(taskLine).join("\n") : "No background tasks.", "info");
    },
  });
}
