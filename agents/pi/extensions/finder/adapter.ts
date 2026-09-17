import {
  createAgentSession,
  DefaultResourceLoader,
  getAgentDir,
  SessionManager,
  type AgentSession,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import {
  bindAbortSignal,
  bindAndPrepareChildSession,
  createActiveSubagentSessionRegistry,
  extractLatestAssistantText,
  shutdownAndDisposeChildSession,
  trackSubagentEvents,
} from "../shared/subagent-runtime.ts";
import {
  createSubagentModelPlan,
  createSubagentSettings,
  type Model,
} from "../shared/subagent-models.ts";
import { promptSubagentWithFailover } from "../shared/subagent-failover.ts";
import {
  assertExecutorMcpToolsRegistered,
  EXECUTOR_MCP_TOOLS,
  isolateExecutorMcpExtension,
  isolatedSubagentResourceDir,
  resolveExecutorMcpExtensionPath,
} from "../shared/subagent-mcp.ts";
import {
  createSubagentRenderers,
  shorten,
  type SubagentDetails,
} from "../shared/subagent-progress.ts";
import subdirContextExtension from "../shared/subdir-context/src/index.ts";
import { FinderParams } from "./finder-core.ts";
import { buildFinderSystemPrompt, buildFinderUserPrompt } from "./finder-prompts.md.ts";

const FINDER_PROVIDER = "openai-codex";
const FINDER_MODEL_ID = "gpt-5.6-luna";
const FINDER_THINKING = "medium" as const;
const FINDER_MODEL = `${FINDER_PROVIDER}/${FINDER_MODEL_ID}`;

export interface FinderDetails extends SubagentDetails<
  "finder",
  typeof FINDER_THINKING,
  { query: string }
> {}

function errorText(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function detailsFor(
  run: FinderDetails["run"],
  cwd: string,
  model = FINDER_MODEL,
): FinderDetails {
  return {
    status: run.status,
    agent: "finder",
    taskLabel: "query",
    workspace: cwd,
    model,
    thinking: FINDER_THINKING,
    run,
    metadata: { query: run.task },
  };
}

function resultFor(
  run: FinderDetails["run"],
  cwd: string,
  text: string,
  isError = false,
  stats?: { tokens?: unknown; cost?: number },
  model = FINDER_MODEL,
) {
  return {
    content: [{ type: "text" as const, text }],
    details: {
      ...detailsFor(run, cwd, model),
      ...stats,
    } satisfies FinderDetails,
    ...(isError ? { isError: true } : {}),
  };
}

async function createFinderSession(
  ctx: ExtensionContext,
  executorMcpExtensionPath: string,
): Promise<{
  session: AgentSession;
  models: Model[];
}> {
  const plan = await createSubagentModelPlan(ctx, FINDER_MODEL_ID);
  const agentDir = getAgentDir();
  const settingsManager = createSubagentSettings(ctx.cwd, agentDir);
  const resourceLoader = new DefaultResourceLoader({
    cwd: ctx.cwd,
    agentDir: isolatedSubagentResourceDir(),
    settingsManager,
    // Load the explicit MCP path plus inline child policies, then discard every
    // other discovered extension before child binding.
    additionalExtensionPaths: [executorMcpExtensionPath],
    extensionFactories: [subdirContextExtension, plan.extensionFactory],
    extensionsOverride: isolateExecutorMcpExtension(executorMcpExtensionPath),
    noSkills: true,
    noPromptTemplates: true,
    noThemes: true,
    noContextFiles: true,
    systemPrompt: buildFinderSystemPrompt(),
  });
  await resourceLoader.reload();

  const { session } = await createAgentSession({
    cwd: ctx.cwd,
    agentDir,
    settingsManager,
    resourceLoader,
    sessionManager: SessionManager.inMemory(ctx.cwd),
    model: plan.models[0],
    thinkingLevel: FINDER_THINKING,
    tools: ["read", "bash", ...EXECUTOR_MCP_TOOLS],
  });
  const boundSession = await bindAndPrepareChildSession(session);
  try {
    assertExecutorMcpToolsRegistered(boundSession);
  } catch (error) {
    await shutdownAndDisposeChildSession(boundSession);
    throw error;
  }
  return {
    session: boundSession,
    models: plan.models,
  };
}

export default function finderExtension(pi: ExtensionAPI) {
  const activeSessions = createActiveSubagentSessionRegistry();
  const sharedRenderers = createSubagentRenderers<FinderDetails>({
    agentLabel: "finder",
    activity: "Searching workspace…",
  });

  pi.on("session_shutdown", async () => {
    await activeSessions.shutdown();
  });

  pi.registerTool({
    name: "finder",
    label: "Finder",
    description:
      "Read-only workspace scout for coding and personal-assistant tasks. Prefer one broad Finder call per task: give it the end goal, likely scope, and hints, and let it do the reconnaissance you would otherwise do manually with ls/rg/fd/read. Finder returns a compact, evidence-backed map: likely entrypoints, core files, nearby config/tests/docs/examples, and key citations.",
    parameters: FinderParams,
    executionMode: "parallel",
    ...sharedRenderers,
    // The shared renderer uses `task`; Finder's public schema uses `query`.
    renderCall(args: unknown, theme: any) {
      const query = typeof (args as { query?: unknown })?.query === "string"
        ? (args as { query: string }).query.trim()
        : "";
      return new Text(
        query ? theme.fg("muted", shorten(query.replace(/\s+/g, " "), 70)) : "",
        0,
        0,
      );
    },
    async execute(
      _toolCallId,
      params,
      signal,
      onUpdate,
      ctx,
    ) {
      const rawQuery = (params as { query?: unknown }).query;
      const query = typeof rawQuery === "string" ? rawQuery.trim() : "";
      const run: FinderDetails["run"] = {
        status: "running",
        task: query,
        turns: 0,
        maxTurns: undefined,
        toolCalls: [],
        startedAt: Date.now(),
      };
      let currentModel = FINDER_MODEL;
      const emitUpdate = (force = false) => {
        onUpdate?.({
          content: [{ type: "text", text: run.summaryText ?? "(searching…)" }],
          details: detailsFor(run, ctx.cwd, currentModel),
        });
      };

      if (!query) {
        const message = "Invalid parameters: expected `query` to be a non-empty string.";
        run.status = "error";
        run.error = message;
        run.summaryText = message;
        run.endedAt = Date.now();
        return resultFor(run, ctx.cwd, message, true, undefined, currentModel);
      }

      emitUpdate(true);
      let session: AgentSession | undefined;
      let stopTracking: (() => void) | undefined;
      let removeAbortListener: (() => void) | undefined;
      let removeActiveSession: (() => void) | undefined;

      try {
        const executorMcpExtensionPath = resolveExecutorMcpExtensionPath(pi);
        const created = await createFinderSession(ctx, executorMcpExtensionPath);
        const child = created.session;
        currentModel = `${created.models[0].provider}/${created.models[0].id}`;
        session = child;
        removeActiveSession = activeSessions.add(child);

        const tracker = trackSubagentEvents(child, {
          run,
          // Intentionally unlimited: Finder is a one-shot scout, not a worker
          // with a soft turn budget.
          updateIntervalMs: 120,
          onUpdate: emitUpdate,
        });
        stopTracking = tracker.unsubscribe;
        removeAbortListener = bindAbortSignal(signal, () => {
          void child.abort().catch(() => undefined);
        });
        if (signal?.aborted) throw new Error("Finder was aborted.");

        await promptSubagentWithFailover(
          child,
          buildFinderUserPrompt(query),
          {
            models: created.models,
            thinkingLevel: FINDER_THINKING,
            signal,
            run,
            onModelChange: (model) => {
              currentModel = `${model.provider}/${model.id}`;
              emitUpdate(true);
            },
          },
        );
        if (signal?.aborted) throw new Error("Finder was aborted.");

        const output = extractLatestAssistantText(child);
        if (!output) throw new Error("Finder returned no final answer.");

        run.status = "done";
        run.summaryText = output;
        run.endedAt = Date.now();
        emitUpdate(true);
        const stats = child.getSessionStats();
        return resultFor(run, ctx.cwd, output, false, {
          tokens: stats.tokens,
          cost: stats.cost,
        }, currentModel);
      } catch (error) {
        const aborted = signal?.aborted || run.terminationReason === "cancelled"
          || run.terminationReason === "shutdown" || errorText(error) === "Finder was aborted.";
        const message = aborted ? "Aborted" : errorText(error);
        run.status = aborted ? "aborted" : "error";
        run.error = aborted ? undefined : message;
        run.summaryText = message;
        run.endedAt = Date.now();
        emitUpdate(true);
        return resultFor(run, ctx.cwd, message, !aborted, undefined, currentModel);
      } finally {
        removeAbortListener?.();
        stopTracking?.();
        removeActiveSession?.();
        if (session) await shutdownAndDisposeChildSession(session);
      }
    },
  });
}
