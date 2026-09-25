import * as fs from "node:fs/promises";
import * as path from "node:path";

import type {
  AgentSession,
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import {
  createAgentSession,
  DefaultResourceLoader,
  getAgentDir,
  SessionManager,
} from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { createSubagentRenderers, shorten } from "../shared/subagent-progress.ts";
import {
  bindAbortSignal,
  bindAndPrepareChildSession,
  createActiveSubagentSessionRegistry,
  extractLatestAssistantText,
  shutdownAndDisposeChildSession,
  trackSubagentEvents,
  type SubagentSessionRegistration,
} from "../shared/subagent-runtime.ts";
import {
  createSubagentModelPlan,
  createSubagentSettings,
  parseExactSubagentModelRef,
  reloadSubagentResources,
  resolveSubagentLifecycleExtensionPaths,
} from "../shared/subagent-models.ts";
import { promptSubagentWithFailover } from "../shared/subagent-failover.ts";
import {
  assertExecutorMcpToolsRegistered,
  EXECUTOR_MCP_TOOLS,
  isolateSubagentExtensions,
  isolatedSubagentResourceDir,
  resolveExecutorMcpExtensionPath,
} from "../shared/subagent-mcp.ts";
import installSubdirContext from "../shared/subdir-context/src/index.ts";
import {
  DEFAULT_MAX_SEARCH_RESULTS,
  DEFAULT_MAX_TURNS,
  LibrarianParams,
  normalizeLibrarianParams,
  type LibrarianDetails,
  type LibrarianMetadata,
  type LibrarianRunDetails,
} from "./core.ts";
import { buildLibrarianSystemPrompt, buildLibrarianUserPrompt } from "./prompt.ts";
import { createTurnBudgetExtension } from "./turn-budget.ts";

const LIBRARIAN_MODEL_PROVIDER = "openai-codex";
const LIBRARIAN_MODEL_ID = "gpt-6-luna";
const LIBRARIAN_THINKING = "high" as const;
const LIBRARIAN_MODEL = `${LIBRARIAN_MODEL_PROVIDER}/${LIBRARIAN_MODEL_ID}`;

function createDetails(
  run: LibrarianRunDetails,
  workspace: string,
  metadata: LibrarianMetadata,
  model = LIBRARIAN_MODEL,
): LibrarianDetails {
  return {
    status: run.status,
    agent: "librarian",
    taskLabel: "GitHub research",
    workspace,
    model,
    thinking: LIBRARIAN_THINKING,
    run,
    metadata,
  };
}

function errorResult(message: string, workspace: string, task = "") {
  const now = Date.now();
  const run: LibrarianRunDetails = {
    status: "error",
    task,
    turns: 0,
    maxTurns: DEFAULT_MAX_TURNS,
    toolCalls: [],
    summaryText: message,
    error: message,
    startedAt: now,
    endedAt: now,
  };
  return {
    content: [{ type: "text" as const, text: message }],
    details: createDetails(run, workspace, {
      repos: [],
      owners: [],
      maxSearchResults: DEFAULT_MAX_SEARCH_RESULTS,
    }),
    isError: true,
  };
}

export default function librarianExtension(pi: ExtensionAPI, registerSession?: SubagentSessionRegistration) {
  const activeSessions = createActiveSubagentSessionRegistry();
  const temporaryWorkspaces = new Set<string>();

  pi.on("session_shutdown", async () => {
    await activeSessions.shutdown();
    await Promise.allSettled(
      [...temporaryWorkspaces].map((workspace) => fs.rm(workspace, { recursive: true, force: true })),
    );
    temporaryWorkspaces.clear();
  });

  pi.registerTool({
    name: "librarian",
    label: "Librarian",
    description:
      "GitHub research scout for coding and personal-assistant tasks. Use when the answer likely lives in GitHub repos, exact repo/path locations are unknown, or you'd otherwise do exploratory gh search/tree probes plus ls/rg/fd/find/grep/read on fetched files. Librarian performs targeted reconnaissance in an isolated workspace and returns concise, path-first findings with line-ranged evidence.",
    parameters: LibrarianParams,
    ...createSubagentRenderers<LibrarianDetails>({
      agentLabel: "Librarian",
      activity: "Searching GitHub…",
    }),
    renderCall(args, theme) {
      const query = typeof (args as { query?: unknown })?.query === "string"
        ? (args as { query: string }).query.trim()
        : "";
      const repos = Array.isArray((args as { repos?: unknown })?.repos)
        ? (args as { repos: unknown[] }).repos.length
        : 0;
      const owners = Array.isArray((args as { owners?: unknown })?.owners)
        ? (args as { owners: unknown[] }).owners.length
        : 0;
      const preview = shorten(query.replace(/\s+/g, " ").trim(), 70);
      const scope = theme.fg("muted", `repos:${repos} owners:${owners}`);
      return new Text(preview ? `${scope} · ${preview}` : scope, 0, 0);
    },
    async execute(toolCallId, params, signal, onUpdate, ctx: ExtensionContext) {
      const normalized = normalizeLibrarianParams(params);
      if ("error" in normalized) {
        return errorResult(normalized.error, ctx.cwd);
      }

      const { query, repos, owners, model: requestedModel, maxSearchResults } = normalized.value;
      let plan: Awaited<ReturnType<typeof createSubagentModelPlan>>;
      let executorMcpExtensionPath: string;
      let selectedModel = LIBRARIAN_MODEL;
      try {
        selectedModel = requestedModel === undefined
          ? LIBRARIAN_MODEL
          : parseExactSubagentModelRef(requestedModel);
        executorMcpExtensionPath = resolveExecutorMcpExtensionPath(pi);
        plan = await createSubagentModelPlan(ctx, selectedModel);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return errorResult(message, ctx.cwd, query);
      }
      const metadata: LibrarianMetadata = { repos, owners, maxSearchResults };
      let currentModel = selectedModel;
      const workspaceBase = "/tmp/pi-librarian";
      await fs.mkdir(workspaceBase, { recursive: true });
      const workspace = await fs.mkdtemp(path.join(workspaceBase, "run-"));
      temporaryWorkspaces.add(workspace);
      await fs.mkdir(path.join(workspace, "repos"), { recursive: true });

      const run: LibrarianRunDetails = {
        status: "running",
        task: query,
        turns: 0,
        maxTurns: DEFAULT_MAX_TURNS,
        toolCalls: [],
        startedAt: Date.now(),
      };
      const buildResultDetails = () => createDetails(run, workspace, metadata, currentModel);
      const emitUpdate = (_force = false) => {
        onUpdate?.({
          content: [{ type: "text", text: run.summaryText ?? "(searching...)" }],
          details: buildResultDetails(),
        });
      };

      emitUpdate(true);

      let session: AgentSession | undefined;
      let stopTracking: (() => void) | undefined;
      let removeAbortListener: (() => void) | undefined;
      let removeActiveSession: (() => void) | undefined;
      let removeSteering: (() => void) | undefined;
      let aborted = false;

      try {
        const systemPrompt = buildLibrarianSystemPrompt(
          DEFAULT_MAX_TURNS,
          workspace,
          maxSearchResults || DEFAULT_MAX_SEARCH_RESULTS,
        );
        const agentDir = getAgentDir();
        const lifecycleExtensionPaths = resolveSubagentLifecycleExtensionPaths(plan, agentDir);
        const allowedExtensionPaths = [executorMcpExtensionPath, ...lifecycleExtensionPaths];
        const settingsManager = createSubagentSettings(workspace, agentDir);
        const resourceLoader = new DefaultResourceLoader({
          cwd: workspace,
          agentDir: isolatedSubagentResourceDir(),
          settingsManager,
          additionalExtensionPaths: allowedExtensionPaths,
          extensionsOverride: isolateSubagentExtensions(allowedExtensionPaths),
          noSkills: true,
          noPromptTemplates: true,
          noThemes: true,
          noContextFiles: true,
          extensionFactories: [
            installSubdirContext,
            createTurnBudgetExtension(DEFAULT_MAX_TURNS),
            plan.extensionFactory,
          ],
          systemPromptOverride: () => systemPrompt,
          skillsOverride: () => ({ skills: [], diagnostics: [] }),
        });
        await reloadSubagentResources(resourceLoader);

        if (signal?.aborted) {
          aborted = true;
          throw new Error("Aborted");
        }

        const created = await createAgentSession({
          cwd: workspace,
          resourceLoader,
          agentDir,
          settingsManager,
          sessionManager: SessionManager.inMemory(workspace),
          model: plan.models[0],
          thinkingLevel: LIBRARIAN_THINKING,
          tools: ["read", "bash", ...EXECUTOR_MCP_TOOLS],
        });
        session = await bindAndPrepareChildSession(created.session);
        assertExecutorMcpToolsRegistered(session);
        currentModel = `${plan.models[0].provider}/${plan.models[0].id}`;
        removeActiveSession = activeSessions.add(session);
        removeSteering = registerSession?.(toolCallId, session);

        const tracker = trackSubagentEvents(session, {
          run,
          updateIntervalMs: 120,
          onUpdate: emitUpdate,
        });
        stopTracking = tracker.unsubscribe;
        removeAbortListener = bindAbortSignal(signal, () => {
          aborted = true;
          void session?.abort().catch(() => undefined);
        });
        if (aborted) throw new Error("Aborted");

        await promptSubagentWithFailover(
          session,
          buildLibrarianUserPrompt(query, repos, owners, maxSearchResults),
          {
            models: plan.models,
            thinkingLevel: LIBRARIAN_THINKING,
            signal,
            run,
            onModelChange: (model) => {
              currentModel = `${model.provider}/${model.id}`;
              emitUpdate(true);
            },
          },
        );
        if (aborted || signal?.aborted) throw new Error("Aborted");

        const output = extractLatestAssistantText(session).trim();
        if (!output) throw new Error("Librarian returned no final answer.");
        run.status = "done";
        run.summaryText = output;
        run.endedAt = Date.now();
        emitUpdate(true);
      } catch (error) {
        const isAborted = aborted || signal?.aborted || run.terminationReason === "cancelled"
          || run.terminationReason === "shutdown";
        run.status = isAborted ? "aborted" : "error";
        run.error = isAborted ? undefined : error instanceof Error ? error.message : String(error);
        run.summaryText = isAborted ? "Aborted" : run.error;
        run.endedAt = Date.now();
        emitUpdate(true);
      } finally {
        removeAbortListener?.();
        stopTracking?.();
        removeSteering?.();
        removeActiveSession?.();
        if (session) await shutdownAndDisposeChildSession(session);
      }

      const details = buildResultDetails();
      return {
        content: [{ type: "text", text: run.summaryText ?? "(no output)" }],
        details,
        isError: run.status === "error",
      };
    },
  });
}
