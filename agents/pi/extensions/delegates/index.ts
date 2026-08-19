import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  createAgentSession,
  DefaultResourceLoader,
  defineTool,
  getAgentDir,
  SessionManager,
  SettingsManager,
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
  shutdownAndDisposeChildSession,
  trackSubagentEvents,
} from "../shared/subagent-runtime.ts";
import {
  DelegateCapacity,
  DELEGATE_CONCURRENCY,
  DELEGATE_POLICIES,
  gitDiffArgs,
  truncateDelegateOutput,
  type DelegateName,
  type GitDiffTarget,
} from "./policy.ts";
import { createSubagentRenderers } from "../shared/subagent-progress.ts";
import { createTurnBudgetExtension } from "../shared/turn-budget.ts";
import {
  type DelegateDetails,
  type DelegateRunDetails,
} from "./progress.ts";

const execFileAsync = promisify(execFile);
const GIT_OUTPUT_LIMIT = 64_000;

const ORACLE_SYSTEM_PROMPT = `You are a read-only oracle providing a rigorous second opinion.

Inspect the relevant code before answering. Focus on architecture, correctness, difficult debugging, plans, and code review. State a clear recommendation, the reasoning behind it, concrete risks, and any assumptions that need validation. Prefer specific file references over generic advice. You cannot modify files or run shell commands.`;

const WORKER_SYSTEM_PROMPT = `You are an implementation worker operating in the current working tree.

Complete only the bounded task you receive. Read the relevant code, make focused changes, and run the most relevant checks. Leave commits, pushes, pull requests, and product decisions to the coordinator. Return a concise summary of changed files, validation results, and unresolved decisions.`;

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
    extensionFactories: [createTurnBudgetExtension(policy.maxTurns)],
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

  return bindAndPrepareChildSession(session);
}

function createDelegateRenderers(name: DelegateName) {
  return createSubagentRenderers<DelegateDetails>({
    agentLabel: name,
    activity: name === "oracle" ? "Consulting Oracle…" : "Working in the repository…",
  });
}

export default function delegatesExtension(pi: ExtensionAPI) {
  const activeSessions = createActiveSubagentSessionRegistry();
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
    let stopTracking: (() => void) | undefined;
    let removeAbortListener: (() => void) | undefined;
    let removeActiveSession: (() => void) | undefined;

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
      const child = await createIsolatedSession({
        name: options.name,
        ctx: options.ctx,
      });
      session = child;
      removeActiveSession = activeSessions.add(child);
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

      await child.prompt(options.task, { expandPromptTemplates: false });
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
      const aborted = options.signal?.aborted ?? false;
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
      removeActiveSession?.();
      if (session) await shutdownAndDisposeChildSession(session);
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
        ...(result.isError ? { isError: true } : {}),
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
        ...(result.isError ? { isError: true } : {}),
      };
    },
  });

  pi.on("session_shutdown", async () => {
    await activeSessions.shutdown();
  });
}
