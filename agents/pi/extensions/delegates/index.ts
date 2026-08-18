import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import {
  createAgentSession,
  DefaultResourceLoader,
  defineTool,
  getAgentDir,
  SessionManager,
  SettingsManager,
  type AgentSession,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
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
    ctx: ExtensionContext;
  }) {
    const releaseCapacity = capacity[options.name].acquire();
    const policy = DELEGATE_POLICIES[options.name];
    let session: AgentSession | undefined;
    let unsubscribe: (() => void) | undefined;
    let abort: (() => void) | undefined;

    try {
      const child = await createIsolatedSession({
        name: options.name,
        ctx: options.ctx,
      });
      session = child;
      activeSessions.add(child);

      let turns = 0;
      let wrapRequested = false;
      let hardAbortRequested = false;
      unsubscribe = child.subscribe((event) => {
        if (event.type !== "turn_end") return;
        turns++;
        if (turns >= policy.maxTurns && !wrapRequested) {
          wrapRequested = true;
          void child
            .steer("Wrap up now. Return your best concise final result without more exploration.")
            .catch(() => undefined);
        } else if (turns >= policy.maxTurns + 2 && !hardAbortRequested) {
          hardAbortRequested = true;
          void child.abort().catch(() => undefined);
        }
      });

      abort = () => {
        void child.abort().catch(() => undefined);
      };
      options.signal?.addEventListener("abort", abort, { once: true });
      if (options.signal?.aborted) throw new Error(`${options.name} was aborted.`);

      await child.prompt(options.task);
      if (options.signal?.aborted) throw new Error(`${options.name} was aborted.`);

      const output = assistantText(child);
      if (!output) throw new Error(`${options.name} returned no final answer.`);
      const result = truncateDelegateOutput(output);
      const stats = child.getSessionStats();
      return {
        text: result.text,
        details: {
          delegate: options.name,
          model: `openai-codex/${policy.model}`,
          thinking: policy.thinking,
          turns,
          toolCalls: stats.toolCalls,
          tokens: stats.tokens,
          cost: stats.cost,
          truncated: result.truncated,
        },
      };
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
    parameters: Type.Object({
      task: Type.String({
        description:
          "Self-contained question, including relevant paths, constraints, and the decision or review needed",
      }),
    }),
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const result = await runDelegate({
        name: "oracle",
        task: params.task,
        signal,
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
    parameters: Type.Object({
      task: Type.String({
        description:
          "Self-contained task with relevant paths, constraints, and the expected validation or result",
      }),
    }),
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const result = await runDelegate({
        name: "worker",
        task: params.task,
        signal,
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
