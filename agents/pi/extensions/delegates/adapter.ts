import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  createAgentSession,
  DefaultResourceLoader,
  defineTool,
  getAgentDir,
  SessionManager,
  type AgentSession,
  type AgentToolUpdateCallback,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  bindAndPrepareChildSession,
  bindAbortSignal,
  createActiveSubagentSessionRegistry,
  describeMissingSubagentOutput,
  extractLatestAssistantText,
  guardReadyChildTools,
  shutdownAndDisposeChildSession,
  trackSubagentEvents,
  type SubagentSessionRegistration,
} from "../shared/subagent-runtime.ts";
import {
  DELEGATE_POLICIES,
  gitDiffArgs,
  truncateDelegateOutput,
  type DelegateName,
  type GitDiffTarget,
} from "./policy.ts";
import { createSubagentRenderers } from "../shared/subagent-progress.ts";
import { createTurnBudgetExtension } from "../shared/turn-budget.ts";
import {
  createSubagentModelPlan,
  createSubagentSettings,
  reloadSubagentResources,
  resolveSubagentLifecycleExtensionPaths,
  type Model,
} from "../shared/subagent-models.ts";
import { promptSubagentWithFailover } from "../shared/subagent-failover.ts";
import {
  createExecutorMcpIntegration,
  EXECUTOR_MCP_TOOLS,
  isolateSubagentExtensions,
  isolatedSubagentResourceDir,
  waitForExecutorTools,
} from "../shared/subagent-mcp.ts";
import { createWorkerWriteScopeExtension } from "../shared/write-scope.ts";
import {
  type DelegateDetails,
  type DelegateRunDetails,
} from "./progress.ts";

const execFileAsync = promisify(execFile);
const GIT_OUTPUT_LIMIT = 64_000;

export const ORACLE_SYSTEM_PROMPT = `You are Oracle, the default read-only analyst for WHY, correctness, root cause, architecture, planning, tradeoffs, and review.

Inspect the relevant code before answering. Explain the reasoning, compare relevant options when asked, identify concrete risks and assumptions, and state what should change when that is the request. Keep recommendations evidence-proportional and scoped to the request. Prefer the simplest direct change. Recommend guardrails, fallbacks, abstractions, or adjacent work only for a concrete failure mode. Separate confirmed findings from assumptions, and surface low-probability risks when their impact is high. Make a decisive recommendation rather than cataloging possibilities. Prefer specific file references over generic advice. You cannot modify files or run shell commands. Executor MCP access is for read-only research only; never invoke an external mutation.`;

const WORKER_SYSTEM_PROMPT = `You are an implementation worker operating in the current working tree.

Complete only the bounded task you receive. Read the relevant code, make focused changes, and run the most relevant checks. Use Executor MCP tools when external integrations are relevant to the task. Leave commits, pushes, pull requests, and product decisions to the coordinator. Return a concise summary of changed files, validation results, and unresolved decisions.`;

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
  writeScope?: string[];
  signal?: AbortSignal;
  onSession(session: AgentSession): void;
}): Promise<{ session: AgentSession; models: Model[]; executorMcp: ReturnType<typeof createExecutorMcpIntegration> }> {
  const { name, ctx, writeScope, signal } = options;
  if (signal?.aborted) throw signal.reason instanceof Error ? signal.reason : new Error(`${name} was aborted.`);
  const executorMcp = createExecutorMcpIntegration();
  const lifetimeSignal = signal ? AbortSignal.any([signal, executorMcp.signal]) : executorMcp.signal;
  const policy = DELEGATE_POLICIES[name];
  const plan = await createSubagentModelPlan(ctx, policy.model);

  const agentDir = getAgentDir();
  const lifecycleExtensionPaths = resolveSubagentLifecycleExtensionPaths(plan, agentDir);
  const allowedExtensionPaths = lifecycleExtensionPaths;
  const settingsManager = createSubagentSettings(ctx.cwd, agentDir);
  const loader = new DefaultResourceLoader({
    cwd: ctx.cwd,
    agentDir: isolatedSubagentResourceDir(),
    settingsManager,
    additionalExtensionPaths: allowedExtensionPaths,
    extensionsOverride: isolateSubagentExtensions(allowedExtensionPaths),
    extensionFactories: [
      (pi) => { pi.on("session_shutdown", () => executorMcp.close()); },
      executorMcp.extensionFactory,
      createTurnBudgetExtension(policy.maxTurns),
      ...(name === "worker" && writeScope?.length
        ? [createWorkerWriteScopeExtension(writeScope)]
        : []),
      plan.extensionFactory,
    ],
    noExtensions: true,
    noSkills: true,
    noPromptTemplates: true,
    noThemes: true,
    noContextFiles: true,
    systemPrompt: name === "oracle" ? ORACLE_SYSTEM_PROMPT : WORKER_SYSTEM_PROMPT,
  });
  await reloadSubagentResources(loader);

  const { session } = await createAgentSession({
    cwd: ctx.cwd,
    agentDir,
    settingsManager,
    resourceLoader: loader,
    sessionManager: SessionManager.inMemory(ctx.cwd),
    model: plan.models[0],
    thinkingLevel: policy.thinking,
    tools: [...policy.tools, ...EXECUTOR_MCP_TOOLS],
    customTools: name === "oracle" ? [createGitDiffTool(ctx.cwd)] : [],
  });

  try {
    // Register ownership before session_start launches any background connection.
    options.onSession(session);
    const boundSession = await bindAndPrepareChildSession(session);
    await waitForExecutorTools(boundSession, lifetimeSignal);
    executorMcp.assertOpen();
    guardReadyChildTools(boundSession);
    return { session: boundSession, models: plan.models, executorMcp };
  } catch (error) {
    await executorMcp.close();
    await shutdownAndDisposeChildSession(session);
    throw error;
  }
}

function createDelegateRenderers(name: DelegateName) {
  return createSubagentRenderers<DelegateDetails>({
    agentLabel: name,
    activity: name === "oracle" ? "Consulting Oracle…" : "Working in the repository…",
  });
}

export default function delegatesExtension(pi: ExtensionAPI, registerSession?: SubagentSessionRegistration) {
  const activeSessions = createActiveSubagentSessionRegistry();

  async function runDelegate(options: {
    name: DelegateName;
    task: string;
    taskId: string;
    signal?: AbortSignal;
    onUpdate?: AgentToolUpdateCallback<DelegateDetails>;
    ctx: ExtensionContext;
    writeScope?: string[];
  }) {
    const policy = DELEGATE_POLICIES[options.name];
    let model = policy.model;
    const run: DelegateRunDetails = {
      status: "running",
      task: options.task,
      turns: 0,
      maxTurns: policy.maxTurns,
      toolCalls: [],
      startedAt: Date.now(),
    };
    let session: AgentSession | undefined;
    let stopTracking: (() => void) | undefined;
    let removeAbortListener: (() => void) | undefined;
    let removeActiveSession: (() => void) | undefined;
    let removeSteering: (() => void) | undefined;

    const buildDetails = (): DelegateDetails => ({
      status: run.status,
      delegate: options.name,
      workspace: options.ctx.cwd,
      model,
      thinking: policy.thinking,
      run,
    });
    const emitUpdate = () => {
      const text = run.summaryText ?? `${options.name} is working…`;
      options.onUpdate?.({
        content: [{ type: "text", text }],
        details: buildDetails(),
      });
    };

    emitUpdate();

    try {
      const created = await createIsolatedSession({
        name: options.name,
        ctx: options.ctx,
        writeScope: options.writeScope,
        signal: options.signal,
        onSession: (child) => {
          session = child;
          removeActiveSession = activeSessions.add(child);
          removeSteering = registerSession?.(options.taskId, child);
        },
      });
      const child = created.session;
      model = `${created.models[0].provider}/${created.models[0].id}`;
      emitUpdate();
      const tracker = trackSubagentEvents(child, {
        run,
        maxTurns: policy.maxTurns,
        onUpdate: () => emitUpdate(),
      });
      stopTracking = tracker.unsubscribe;
      removeAbortListener = bindAbortSignal(options.signal, () => {
        void child.abort().catch(() => undefined);
      });
      if (options.signal?.aborted) throw new Error(`${options.name} was aborted.`);

      created.executorMcp.assertOpen();
      await promptSubagentWithFailover(child, options.task, {
        models: created.models,
        thinkingLevel: policy.thinking,
        signal: options.signal ? AbortSignal.any([options.signal, created.executorMcp.signal]) : created.executorMcp.signal,
        run,
        onModelChange: (candidate) => {
          model = `${candidate.provider}/${candidate.id}`;
          emitUpdate();
        },
      });
      if (options.signal?.aborted) throw new Error(`${options.name} was aborted.`);

      const output = extractLatestAssistantText(child);
      const stats = child.getSessionStats();
      if (run.terminationReason === "turn_limit" || !output) {
        const missing = describeMissingSubagentOutput(options.name, run);
        run.status = "error";
        run.terminationReason = missing.terminationReason;
        run.error = missing.message;
        run.summaryText = missing.message;
        run.endedAt = Date.now();
        emitUpdate();
        return {
          text: missing.message,
          details: {
            ...buildDetails(),
            tokens: stats.tokens,
            cost: stats.cost,
          } satisfies DelegateDetails,
          isError: true,
        };
      }

      const result = truncateDelegateOutput(output);
      run.status = "done";
      run.terminationReason = "completed";
      run.summaryText = result.text;
      run.endedAt = Date.now();
      emitUpdate();

      return {
        text: result.text,
        details: {
          ...buildDetails(),
          tokens: stats.tokens,
          cost: stats.cost,
          truncated: result.truncated,
        } satisfies DelegateDetails,
        isError: false,
      };
    } catch (error) {
      const aborted = options.signal?.aborted || run.terminationReason === "cancelled"
        || run.terminationReason === "shutdown";
      const turnLimited = run.terminationReason === "turn_limit";
      run.status = aborted ? "aborted" : "error";
      run.terminationReason = aborted
        ? "cancelled"
        : run.terminationReason ?? "prompt_error";
      const message = turnLimited
        ? describeMissingSubagentOutput(options.name, run).message
        : error instanceof Error ? error.message : String(error);
      run.error = aborted ? undefined : message;
      run.summaryText = aborted ? "Aborted" : message;
      run.endedAt = Date.now();
      emitUpdate();
      return {
        text: run.summaryText ?? "Aborted",
        details: buildDetails(),
        isError: !aborted,
      };
    } finally {
      removeAbortListener?.();
      stopTracking?.();
      removeSteering?.();
      removeActiveSession?.();
      if (session) await shutdownAndDisposeChildSession(session);
    }
  }

  pi.registerTool({
    name: "oracle",
    label: "Ask Oracle",
    description:
      "Ask Oracle, the default read-only Astra xhigh analyst for WHY, correctness, root cause, architecture, planning, tradeoffs, review, and what should change. Provide a self-contained question with relevant paths and constraints. Use Mapper only for WHERE/WHAT location and evidence.",
    promptSnippet: "Ask Oracle for default read-only WHY/correctness/what-should-change analysis",
    promptGuidelines: [
      "Use oracle by default for WHY, correctness, root cause, architecture, planning, tradeoffs, review, or what should change; give it a self-contained question with relevant paths and constraints.",
      "Use Mapper for WHERE/WHAT only: locating files, symbols, config, tests, dependencies, and explicit call/data-flow anchors with file:line evidence.",
      "Independent oracle calls may run concurrently and alongside independent workers.",
    ],
    executionMode: "parallel",
    ...createDelegateRenderers("oracle"),
    parameters: Type.Object({
      task: Type.String({
        description:
          "Self-contained question, including relevant paths, constraints, and the decision or review needed",
      }),
    }),
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const result = await runDelegate({
        name: "oracle",
        taskId: toolCallId,
        task: params.task,
        signal,
        onUpdate,
        ctx,
      });
      return {
        content: [{ type: "text", text: result.text }],
        details: result.details,
        ...(result.isError ? { isError: true } : {}),
      };
    },
  });

  pi.registerTool({
    name: "worker",
    label: "Delegate Work",
    description:
      "Delegate a bounded implementation, test, or CI-diagnosis task to a fresh GPT-6.1 Sol high worker. Provide relevant paths, constraints, and a checkable completion condition. The worker edits the current working tree but does not commit or push.",
    promptSnippet: "Delegate bounded implementation, testing, or CI diagnosis to a fresh GPT-6.1 Sol worker",
    promptGuidelines: [
      "Use worker for bounded implementation, tests, routine refactors, or CI diagnosis; include relevant paths, constraints, and a checkable completion condition.",
      "Launch independent worker calls in the same response when they have disjoint file ownership; Pi runs those calls concurrently.",
      "Review worker changes and test evidence before committing or pushing.",
    ],
    executionMode: "parallel",
    ...createDelegateRenderers("worker"),
    parameters: Type.Object({
      task: Type.String({
        description:
          "Self-contained task with relevant paths, constraints, and the expected validation or result",
      }),
      writeScope: Type.Optional(Type.Array(Type.String(), {
        description: "Canonical Worker write paths supplied by the background task coordinator.",
      })),
    }),
    async execute(toolCallId, params, signal, onUpdate, ctx) {
      const result = await runDelegate({
        name: "worker",
        taskId: toolCallId,
        task: params.task,
        signal,
        onUpdate,
        ctx,
        writeScope: params.writeScope,
      });
      return {
        content: [{ type: "text", text: result.text }],
        details: result.details,
        ...(result.isError ? { isError: true } : {}),
      };
    },
  });

  pi.on("session_shutdown", async () => {
    await activeSessions.shutdown();
  });
}
