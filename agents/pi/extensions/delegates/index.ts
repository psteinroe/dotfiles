import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import {
  createAgentSession,
  DefaultResourceLoader,
  defineTool,
  getAgentDir,
  getMarkdownTheme,
  SessionManager,
  SettingsManager,
  type AgentSession,
  type AgentToolUpdateCallback,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { Container, Markdown, Spacer, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import {
  bindChildSessionExtensions,
  shutdownAndDisposeChildSession,
} from "../shared/child-session.ts";
import {
  DelegateCapacity,
  DELEGATE_CONCURRENCY,
  DELEGATE_POLICIES,
  gitDiffArgs,
  truncateDelegateOutput,
  type DelegateName,
  type GitDiffTarget,
} from "./policy.ts";
import {
  formatToolCall,
  MAX_TOOL_CALLS_TO_KEEP,
  shorten,
  type DelegateDetails,
  type DelegateRunDetails,
} from "./progress.ts";

const execFileAsync = promisify(execFile);
const GIT_OUTPUT_LIMIT = 64_000;

const ORACLE_SYSTEM_PROMPT = `You are a read-only oracle providing a rigorous second opinion.

Inspect the relevant code before answering. Focus on architecture, correctness, difficult debugging, plans, and code review. State a clear recommendation, the reasoning behind it, concrete risks, and any assumptions that need validation. Prefer specific file references over generic advice. You cannot modify files or run shell commands.`;

const WORKER_SYSTEM_PROMPT = `You are an implementation worker operating in the current working tree.

Complete only the bounded task you receive. Read the relevant code, make focused changes, and run the most relevant checks. Leave commits, pushes, pull requests, and product decisions to the coordinator. Return a concise summary of changed files, validation results, and unresolved decisions.`;

function assistantText(session: AgentSession) {
  for (let index = session.messages.length - 1; index >= 0; index--) {
    const message = session.messages[index];
    if ((message as { role?: string }).role !== "assistant") continue;
    const text = (message as AssistantMessage).content
      .filter((part) => part.type === "text")
      .map((part) => part.text)
      .join("\n")
      .trim();
    if (text) return text;
  }
  return "";
}

function createGitDiffTool(cwd: string) {
  return defineTool({
    name: "git_diff",
    label: "Read Git Diff",
    description:
      "Read the working-tree diff, staged diff, or current HEAD commit without allowing arbitrary shell commands.",
    parameters: Type.Object({
      target: Type.Union(
        [Type.Literal("working"), Type.Literal("staged"), Type.Literal("head")],
        { description: "Which change set to inspect" },
      ),
    }),
    async execute(_toolCallId, params) {
      const target = params.target as GitDiffTarget;
      const { stdout, stderr } = await execFileAsync("git", gitDiffArgs(target), {
        cwd,
        encoding: "utf8",
        maxBuffer: 2 * 1024 * 1024,
      });
      const raw = stdout || stderr || "No diff output.";
      const result = truncateDelegateOutput(raw, GIT_OUTPUT_LIMIT);
      return {
        content: [{ type: "text", text: result.text }],
        details: { target, truncated: result.truncated },
      };
    },
  });
}

async function createIsolatedSession(options: {
  name: DelegateName;
  ctx: ExtensionContext;
}) {
  const { name, ctx } = options;
  const policy = DELEGATE_POLICIES[name];
  const model = ctx.modelRegistry.find("openai-codex", policy.model);
  if (!model) {
    throw new Error(`Required model is unavailable: openai-codex/${policy.model}`);
  }

  const agentDir = getAgentDir();
  const settingsManager = SettingsManager.create(ctx.cwd, agentDir, {
    projectTrusted: false,
  });
  const loader = new DefaultResourceLoader({
    cwd: ctx.cwd,
    agentDir,
    settingsManager,
    noExtensions: true,
    noSkills: true,
    noPromptTemplates: true,
    noThemes: true,
    noContextFiles: true,
    systemPrompt: name === "oracle" ? ORACLE_SYSTEM_PROMPT : WORKER_SYSTEM_PROMPT,
  });
  await loader.reload();

  const { session } = await createAgentSession({
    cwd: ctx.cwd,
    agentDir,
    settingsManager,
    resourceLoader: loader,
    sessionManager: SessionManager.inMemory(ctx.cwd),
    model,
    thinkingLevel: policy.thinking,
    tools: [...policy.tools],
    customTools: name === "oracle" ? [createGitDiffTool(ctx.cwd)] : [],
  });

  try {
    await bindChildSessionExtensions(session);
  } catch (error) {
    await shutdownAndDisposeChildSession(session);
    throw error;
  }

  return session;
}

// Rendering follows the progress UI used by pi-finder and pi-librarian.
function createDelegateRenderers(name: DelegateName) {
  const activity = name === "oracle" ? "Consulting Oracle…" : "Working in the repository…";

  return {
    renderCall(args: unknown, theme: any) {
      const task = typeof (args as { task?: unknown })?.task === "string"
        ? (args as { task: string }).task.trim()
        : "";
      return new Text(theme.fg("muted", shorten(task.replace(/\s+/g, " "), 70)), 0, 0);
    },

    renderResult(result: any, { expanded, isPartial }: any, theme: any) {
      const details = result.details as DelegateDetails | undefined;
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
      const header = icon + " "
        + theme.fg("toolTitle", theme.bold(`${name} `))
        + theme.fg(
          "dim",
          `${details.model}:${details.thinking} • ${run.turns}/${run.maxTurns} turns • ${totalToolCalls} tool call${totalToolCalls === 1 ? "" : "s"}`,
        );
      const workspaceLine = `${theme.fg("muted", "workspace: ")}${theme.fg("toolOutput", details.workspace)}`;

      let toolsText = "";
      if (run.toolCalls.length > 0) {
        const calls = expanded ? run.toolCalls : run.toolCalls.slice(-6);
        const lines: string[] = [theme.fg("muted", "Tools:")];
        for (const call of calls) {
          const callIcon = call.isError
            ? theme.fg("error", "✗")
            : call.endedAt
              ? theme.fg("success", "✓")
              : theme.fg("warning", "→");
          lines.push(`${callIcon} ${theme.fg("toolOutput", formatToolCall(call))}`);
        }
        if (!expanded && run.toolCalls.length > 6) {
          lines.push(theme.fg("muted", "(Ctrl+O to expand)"));
        }
        toolsText = lines.join("\n");
      }

      if (status === "running") {
        let text = `${header}\n${workspaceLine}`;
        if (toolsText) text += `\n\n${toolsText}`;
        text += `\n\n${theme.fg("muted", activity)}`;
        return new Text(text, 0, 0);
      }

      const combined = (
        result.content[0]?.type === "text"
          ? result.content[0].text
          : run.summaryText ?? "(no output)"
      ).trim() || "(no output)";

      if (!expanded) {
        const lines = combined.split("\n");
        let text = `${header}\n${workspaceLine}\n\n${theme.fg("toolOutput", lines.slice(0, 18).join("\n"))}`;
        if (lines.length > 18) text += `\n${theme.fg("muted", "(Ctrl+O to expand)")}`;
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

export default function delegatesExtension(pi: ExtensionAPI) {
  const activeSessions = new Set<AgentSession>();
  const capacity: Record<DelegateName, DelegateCapacity> = {
    oracle: new DelegateCapacity(DELEGATE_CONCURRENCY.oracle),
    worker: new DelegateCapacity(DELEGATE_CONCURRENCY.worker),
  };

  async function runDelegate(options: {
    name: DelegateName;
    task: string;
    signal?: AbortSignal;
    onUpdate?: AgentToolUpdateCallback<DelegateDetails>;
    ctx: ExtensionContext;
  }) {
    const releaseCapacity = capacity[options.name].acquire();
    const policy = DELEGATE_POLICIES[options.name];
    const model = `openai-codex/${policy.model}`;
    const run: DelegateRunDetails = {
      status: "running",
      task: options.task,
      turns: 0,
      maxTurns: policy.maxTurns,
      toolCalls: [],
      startedAt: Date.now(),
    };
    let session: AgentSession | undefined;
    let unsubscribe: (() => void) | undefined;
    let abort: (() => void) | undefined;
    let lastUpdate = 0;

    const buildDetails = (): DelegateDetails => ({
      status: run.status,
      delegate: options.name,
      workspace: options.ctx.cwd,
      model,
      thinking: policy.thinking,
      run,
    });
    const emitUpdate = (force = false) => {
      const now = Date.now();
      if (!force && now - lastUpdate < 120) return;
      lastUpdate = now;
      const text = run.summaryText ?? `${options.name} is working…`;
      options.onUpdate?.({
        content: [{ type: "text", text }],
        details: buildDetails(),
      });
    };

    emitUpdate(true);

    try {
      const child = await createIsolatedSession({
        name: options.name,
        ctx: options.ctx,
      });
      session = child;
      activeSessions.add(child);

      let wrapRequested = false;
      let hardAbortRequested = false;
      unsubscribe = child.subscribe((event) => {
        switch (event.type) {
          case "turn_end": {
            run.turns++;
            if (run.turns >= policy.maxTurns && !wrapRequested) {
              wrapRequested = true;
              void child
                .steer("Wrap up now. Return your best concise final result without more exploration.")
                .catch(() => undefined);
            } else if (run.turns >= policy.maxTurns + 2 && !hardAbortRequested) {
              hardAbortRequested = true;
              void child.abort().catch(() => undefined);
            }
            emitUpdate();
            break;
          }
          case "tool_execution_start": {
            run.toolCalls.push({
              id: event.toolCallId,
              name: event.toolName,
              args: event.args,
              startedAt: Date.now(),
            });
            if (run.toolCalls.length > MAX_TOOL_CALLS_TO_KEEP) {
              run.toolCalls.splice(0, run.toolCalls.length - MAX_TOOL_CALLS_TO_KEEP);
            }
            emitUpdate(true);
            break;
          }
          case "tool_execution_end": {
            const call = run.toolCalls.find((candidate) => candidate.id === event.toolCallId);
            if (call) {
              call.endedAt = Date.now();
              call.isError = event.isError;
            }
            emitUpdate(true);
            break;
          }
        }
      });

      abort = () => {
        void child.abort().catch(() => undefined);
      };
      options.signal?.addEventListener("abort", abort, { once: true });
      if (options.signal?.aborted) throw new Error(`${options.name} was aborted.`);

      await child.prompt(options.task, { expandPromptTemplates: false });
      if (options.signal?.aborted) throw new Error(`${options.name} was aborted.`);

      const output = assistantText(child);
      if (!output) throw new Error(`${options.name} returned no final answer.`);
      const result = truncateDelegateOutput(output);
      const stats = child.getSessionStats();
      run.status = "done";
      run.summaryText = result.text;
      run.endedAt = Date.now();
      emitUpdate(true);

      return {
        text: result.text,
        details: {
          ...buildDetails(),
          tokens: stats.tokens,
          cost: stats.cost,
          truncated: result.truncated,
        } satisfies DelegateDetails,
      };
    } catch (error) {
      const aborted = options.signal?.aborted ?? false;
      run.status = aborted ? "aborted" : "error";
      run.error = aborted ? undefined : error instanceof Error ? error.message : String(error);
      run.summaryText = aborted ? "Aborted" : run.error;
      run.endedAt = Date.now();
      emitUpdate(true);
      throw error;
    } finally {
      if (abort) options.signal?.removeEventListener("abort", abort);
      unsubscribe?.();
      if (session) {
        activeSessions.delete(session);
        await shutdownAndDisposeChildSession(session);
      }
      releaseCapacity();
    }
  }

  pi.registerTool({
    name: "oracle",
    label: "Ask Oracle",
    description:
      "Ask a read-only Sol xhigh second opinion for architecture, consequential plans, difficult debugging, or independent review. Provide a self-contained question with relevant paths and constraints. Do not use for routine work.",
    promptSnippet: "Ask a read-only Sol xhigh oracle for a consequential second opinion",
    promptGuidelines: [
      "Use oracle for consequential architecture, difficult debugging, ambiguous plans, or independent review; give it a self-contained question with relevant paths and constraints.",
      "Run at most one oracle at a time; it may run alongside independent workers.",
    ],
    executionMode: "parallel",
    ...createDelegateRenderers("oracle"),
    parameters: Type.Object({
      task: Type.String({
        description:
          "Self-contained question, including relevant paths, constraints, and the decision or review needed",
      }),
    }),
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const result = await runDelegate({
        name: "oracle",
        task: params.task,
        signal,
        onUpdate,
        ctx,
      });
      return {
        content: [{ type: "text", text: result.text }],
        details: result.details,
      };
    },
  });

  pi.registerTool({
    name: "worker",
    label: "Delegate Work",
    description:
      "Delegate a bounded implementation, test, or CI-diagnosis task to a fresh Luna high worker. Provide relevant paths, constraints, and a checkable completion condition. The worker edits the current working tree but does not commit or push.",
    promptSnippet: "Delegate bounded implementation, testing, or CI diagnosis to a fresh Luna worker",
    promptGuidelines: [
      "Use worker for bounded implementation, tests, routine refactors, or CI diagnosis; include relevant paths, constraints, and a checkable completion condition.",
      "Launch up to four independent worker calls in the same response when they have disjoint file ownership; Pi runs those calls concurrently.",
      "Review worker changes and test evidence before committing or pushing.",
    ],
    executionMode: "parallel",
    ...createDelegateRenderers("worker"),
    parameters: Type.Object({
      task: Type.String({
        description:
          "Self-contained task with relevant paths, constraints, and the expected validation or result",
      }),
    }),
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const result = await runDelegate({
        name: "worker",
        task: params.task,
        signal,
        onUpdate,
        ctx,
      });
      return {
        content: [{ type: "text", text: result.text }],
        details: result.details,
      };
    },
  });

  pi.on("session_shutdown", async () => {
    const sessions = [...activeSessions];
    activeSessions.clear();
    await Promise.all(
      sessions.map(async (session) => {
        await session.abort().catch(() => undefined);
        await shutdownAndDisposeChildSession(session);
      }),
    );
  });
}
