import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createServer, type Server } from "node:http";
import { tmpdir } from "node:os";
import * as path from "node:path";
import test from "node:test";
import {
  createAssistantMessageEventStream,
  createProvider,
  type Api,
  type AssistantMessage,
  type AssistantMessageEventStream,
  type Context,
  type Model,
  type Provider,
  type StreamOptions,
} from "@earendil-works/pi-ai";
import {
  createAgentSession,
  DefaultResourceLoader,
  ModelRuntime,
  SessionManager,
  SettingsManager,
  type AgentSession,
  type ExtensionFactory,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { shutdownAndDisposeChildSession } from "./child-session.ts";
import { isolatedSubagentResourceDir } from "./subagent-mcp.ts";
import { Type } from "typebox";

const MODEL_ID = "gpt-6-luna";
const ORACLE_MODEL_ID = "gpt-6-astra";
const WORKER_MODEL_ID = "gpt-6.1-sol";
const PRIMARY = "openai-codex";
const ALIAS = "openai-codex-account-1";
const API = "openai-responses" as Api;

type Role = "mapper" | "librarian" | "worker" | "oracle";
type FixtureMode = "failover" | "all-fail" | "aborted";
type Call = {
  provider: string;
  role: Role;
  model: string;
  reasoning: string | undefined;
  tools: string[];
  context: Context["messages"];
};

const EXECUTOR_TOOLS = ["mcp__executor__execute", "mcp__executor__resume", "mcp__executor__skills"];
const EXPECTED: Record<Role, { model: string; thinking: "medium" | "high" | "xhigh"; tools: string[] }> = {
  mapper: { model: MODEL_ID, thinking: "medium", tools: ["find", "grep", "ls", "read"] },
  librarian: { model: MODEL_ID, thinking: "high", tools: ["bash", ...EXECUTOR_TOOLS, "read"] },
  worker: { model: WORKER_MODEL_ID, thinking: "high", tools: ["bash", "edit", ...EXECUTOR_TOOLS, "find", "grep", "ls", "read", "write"] },
  oracle: { model: ORACLE_MODEL_ID, thinking: "xhigh", tools: [...EXECUTOR_TOOLS, "find", "git_diff", "grep", "ls", "read"] },
};

function model(provider: string, id = MODEL_ID): Model<Api> {
  return {
    id,
    name: `${provider}/${id}`,
    api: API,
    provider,
    baseUrl: "http://failover.invalid",
    reasoning: true,
    thinkingLevelMap: { off: "off", minimal: "minimal", low: "low", medium: "medium", high: "high", xhigh: "xhigh" },
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 20_000,
    maxTokens: 500,
  } as Model<Api>;
}

function assistantMessage(
  provider: string,
  modelId: string,
  content: AssistantMessage["content"],
  stopReason: AssistantMessage["stopReason"],
  errorMessage?: string,
): AssistantMessage {
  return {
    role: "assistant",
    content,
    api: API,
    provider,
    model: modelId,
    usage: {
      input: 1,
      output: content.length,
      cacheRead: 0,
      cacheWrite: 0,
      totalTokens: 1 + content.length,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
    },
    stopReason,
    ...(errorMessage ? { errorMessage } : {}),
    timestamp: Date.now(),
  };
}

function fixtureStream(
  id: string,
  calls: Call[],
  mode: FixtureMode,
  workspace: string,
): (fixtureModel: Model<Api>, context: Context, options?: StreamOptions & { reasoning?: string }) => AssistantMessageEventStream {
  return (fixtureModel, context, options) => {
    // Pi 0.86+ carries the rendered system prompt in transcript messages;
    // retain the legacy field too so this fixture covers both host formats.
    const system = [
      context.systemPrompt ?? "",
      JSON.stringify(context.messages.filter((message) => message.role === "system")),
    ].join("\n");
    const role: Role = system.includes("Mapper")
      ? "mapper"
      : system.includes("Librarian")
        ? "librarian"
        : system.includes("oracle") || system.includes("Oracle")
          ? "oracle"
          : "worker";
    calls.push({
      provider: id,
      role,
      model: fixtureModel.id,
      reasoning: options?.reasoning,
      tools: (
        context.tools?.length
          ? context.tools
          : context.messages
            .filter((message) => message.role === "system")
            .flatMap((message) => message.toolsAdded ?? [])
      ).map((tool) => tool.name),
      context: structuredClone(context.messages),
    });

    const streamResult = createAssistantMessageEventStream();
    const isPrimary = id === PRIMARY;
    const hasToolResult = context.messages.some((message) => message.role === "toolResult");
    let message: AssistantMessage;
    if (mode === "aborted") {
      message = assistantMessage(id, fixtureModel.id, [], "aborted", "aborted fixture response");
    } else if (mode === "all-fail" || isPrimary && (!role || role !== "worker" || hasToolResult)) {
      // Distinct provider errors make it impossible for a stale commentary result
      // to masquerade as a successful failover response.
      const status = role === "librarian" ? "429" : "401";
      message = assistantMessage(id, fixtureModel.id, [], "error", `${status} fixture failure`);
    } else if (isPrimary && role === "worker" && !hasToolResult) {
      message = assistantMessage(id, fixtureModel.id, [{
        type: "toolCall",
        id: "write-once",
        name: "write",
        arguments: { path: path.join(workspace, "worker-output.txt"), content: "written exactly once\n" },
      }], "toolUse");
    } else {
      message = assistantMessage(id, fixtureModel.id, [{ type: "text", text: `${role.toUpperCase()}_${id === ALIAS ? "ALIAS" : "PRIMARY"}_OK` }], "stop");
    }
    queueMicrotask(() => {
      if (message.stopReason === "error" || message.stopReason === "aborted") {
        streamResult.push({ type: "error", reason: message.stopReason, error: message });
      } else {
        streamResult.push({ type: "done", reason: message.stopReason as "stop" | "toolUse", message });
      }
      streamResult.end(message);
    });
    return streamResult;
  };
}

type LegacyProviderConfig = Parameters<ModelRuntime["registerProvider"]>[1];

function legacyFixtureProviderConfig(
  id: string,
  calls: Call[],
  mode: FixtureMode,
  workspace: string,
): LegacyProviderConfig {
  const streamSimple = fixtureStream(id, calls, mode, workspace);
  return {
    name: `fixture ${id}`,
    baseUrl: "http://failover.invalid",
    api: API,
    oauth: {
      name: `temporary synthetic fixture OAuth (${id})`,
      async login() {
        return { refresh: `fixture-${id}-refresh`, access: `fixture-${id}-access`, expires: Date.now() + 3_600_000 };
      },
      async refreshToken(credentials) {
        return { ...credentials, access: `fixture-${id}-refreshed`, expires: Date.now() + 3_600_000 };
      },
      getApiKey(credentials) {
        return credentials.access;
      },
    },
    models: [MODEL_ID, ORACLE_MODEL_ID, WORKER_MODEL_ID].map((modelId) => {
      const candidate = model(id, modelId);
      return {
        id: candidate.id,
        name: candidate.name,
        api: candidate.api,
        baseUrl: candidate.baseUrl,
        reasoning: candidate.reasoning,
        thinkingLevelMap: candidate.thinkingLevelMap,
        input: candidate.input,
        cost: candidate.cost,
        contextWindow: candidate.contextWindow,
        maxTokens: candidate.maxTokens,
      };
    }),
    // This is the legacy pi-multi-account registration shape: the custom
    // request function lives on the config, while OAuth is adapted by Pi.
    streamSimple,
  };
}

function fixtureProvider(id: string, calls: Call[], mode: FixtureMode, workspace: string): Provider {
  const stream = fixtureStream(id, calls, mode, workspace);
  return createProvider({
    id,
    name: `fixture ${id}`,
    auth: {
      apiKey: {
        name: "temporary synthetic fixture key",
        resolve: async () => ({ auth: { apiKey: `fixture-${id}` }, source: "integration fixture" }),
      },
    },
    models: [model(id, MODEL_ID), model(id, ORACLE_MODEL_ID), model(id, WORKER_MODEL_ID)],
    api: { stream, streamSimple: stream },
  });
}

type McpFixtureMode = "ready" | "delayed" | "unauthorized" | "partial" | "hanging";

async function harness(mode: FixtureMode = "failover", registration: "native" | "legacy" = "native", mcpMode: McpFixtureMode = "ready") {
  const root = await mkdtemp(path.join(tmpdir(), "pi-failover-integration-"));
  const previousAgentDir = process.env.PI_CODING_AGENT_DIR;
  process.env.PI_CODING_AGENT_DIR = path.join(root, "agent");
  let parentSession: AgentSession | undefined;
  let mcpServer: Server | undefined;
  let maliciousExtension: string | undefined;
  const children: AgentSession[] = [];
  const toolSnapshots: Array<{ active: string[]; callable: string[] }> = [];
  let resolveInitialization!: () => void;
  let releaseInitialization!: () => void;
  let resolveSessionClosed!: () => void;
  const initializationStarted = new Promise<void>((resolve) => { resolveInitialization = resolve; });
  const initializationGate = new Promise<void>((resolve) => { releaseInitialization = resolve; });
  const sessionClosed = new Promise<void>((resolve) => { resolveSessionClosed = resolve; });
  let initialized = 0;
  const registerChild = (_id: string, child: AgentSession) => {
    children.push(child);
    return child.subscribe((event) => {
      if (event.type === "agent_start") toolSnapshots.push({ active: child.getActiveToolNames(), callable: child.getCallableToolNames() });
    });
  };
  try {
    const agentDir = path.join(root, "agent");
    const workspace = path.join(root, "workspace");
  await mkdir(agentDir, { recursive: true });
  await mkdir(workspace, { recursive: true });
  const settings = {
    defaultProvider: PRIMARY,
    defaultModel: "parent-model",
    defaultThinkingLevel: "low",
    theme: "parent-theme",
    retry: { enabled: true, maxRetries: 7, provider: { maxRetries: 3, timeoutMs: 111 } },
  };
  await writeFile(path.join(agentDir, "settings.json"), JSON.stringify(settings));
  mcpServer = createServer(async (request, response) => {
    if (request.method === "DELETE") { resolveSessionClosed(); response.writeHead(204).end(); return; }
    if (request.method !== "POST") { response.writeHead(404).end(); return; }
    const chunks: Buffer[] = [];
    for await (const chunk of request) chunks.push(Buffer.from(chunk));
    let message: any;
    try { message = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { response.writeHead(400).end(); return; }
    if (message.method?.startsWith("notifications/")) { response.writeHead(202).end(); return; }
    let result: any = {};
    if (message.method === "initialize") {
      initialized++;
      resolveInitialization();
      if (mcpMode === "hanging") await initializationGate;
      if (response.destroyed) return;
      if (mcpMode === "unauthorized") { response.writeHead(401).end(); return; }
      result = { protocolVersion: "2025-03-26", capabilities: { tools: {}, resources: {} }, serverInfo: { name: "executor-fixture", version: "1" } };
    }
    else if (message.method === "tools/list") {
      if (mcpMode === "delayed") await new Promise<void>((resolve) => setTimeout(resolve, 80));
      if (response.destroyed) return;
      result = { tools: (mcpMode === "partial" ? ["execute", "skills"] : ["execute", "skills", "resume", "extra"]).map((name) => ({ name, description: "Fixture", inputSchema: { type: "object", properties: {} } })) };
    }
    else if (message.method === "resources/list") result = { resources: [{ uri: "file:///secret", name: "secret" }] };
    else if (message.method === "resources/templates/list") result = { resourceTemplates: [] };
    else if (message.method === "tools/call") result = { content: [{ type: "text", text: "fixture" }] };
    response.writeHead(200, { "content-type": "application/json", "mcp-session-id": "fixture-session" }).end(JSON.stringify({ jsonrpc: "2.0", id: message.id, result }));
  });
  await new Promise<void>((resolve) => mcpServer!.listen(0, "127.0.0.1", resolve));
  const address = mcpServer.address() as { port: number };
  const maliciousMarker = path.join(root, "unrelated-mcp-or-extension-loaded");
  await writeFile(path.join(agentDir, "mcp.json"), JSON.stringify({ mcpServers: {
    executor: { url: `http://127.0.0.1:${address.port}/mcp`, toolExposure: { "*": "direct" }, resourcesExposure: "direct" },
    unrelated: { command: process.execPath, args: ["-e", `require('node:fs').writeFileSync(${JSON.stringify(maliciousMarker)}, 'bad')`] },
  } }));
  await mkdir(path.join(workspace, ".pi"), { recursive: true });
  await writeFile(path.join(workspace, ".pi", "mcp.json"), JSON.stringify({ mcpServers: { executor: { url: "http://127.0.0.1:1/override-must-not-connect" } } }));

  const calls: Call[] = [];
  const authPath = path.join(agentDir, "auth.json");
  if (registration === "legacy") {
    // Keep these OAuth records synthetic but structurally valid. Both the parent
    // and the fresh child runtime must be able to resolve the effective provider
    // without installing pi-multi-account or contacting an auth endpoint.
    await writeFile(authPath, JSON.stringify({
      [PRIMARY]: { type: "oauth", refresh: "fixture-primary-refresh", access: "fixture-primary-access", expires: Date.now() + 3_600_000 },
      [ALIAS]: { type: "oauth", refresh: "fixture-alias-refresh", access: "fixture-alias-access", expires: Date.now() + 3_600_000 },
    }));
  }
  const runtime = await ModelRuntime.create({
    authPath,
    modelsPath: null,
    allowModelNetwork: false,
  });
  if (registration === "legacy") {
    runtime.registerProvider(PRIMARY, legacyFixtureProviderConfig(PRIMARY, calls, mode, workspace));
    runtime.registerProvider(ALIAS, legacyFixtureProviderConfig(ALIAS, calls, mode, workspace));
  } else {
    runtime.registerNativeProvider(fixtureProvider(PRIMARY, calls, mode, workspace));
    runtime.registerNativeProvider(fixtureProvider(ALIAS, calls, mode, workspace));
  }
  await runtime.refresh();

  let parentContext: ExtensionContext | undefined;
  const unrelated: ExtensionFactory = (pi) => {
    pi.registerTool({
      name: "unrelated_parent_tool",
      label: "Unrelated parent tool",
      description: "Must not leak into isolated children.",
      parameters: Type.Object({}),
      async execute() { return { content: [{ type: "text", text: "unrelated" }], details: {} }; },
    });
    pi.on("session_start", (_event, ctx) => { parentContext = ctx; });
  };
  const [{ default: mapper }, { default: librarian }, { default: delegates }] = await Promise.all([
    import("../finder/adapter.ts"),
    import("../librarian/adapter.ts"),
    import("../delegates/adapter.ts"),
  ]);
  const loader = new DefaultResourceLoader({
    cwd: workspace,
    agentDir,
    settingsManager: SettingsManager.create(workspace, agentDir, { projectTrusted: false }),
    additionalExtensionPaths: [],
    extensionFactories: [unrelated, (pi) => mapper(pi, registerChild), (pi) => librarian(pi, registerChild), (pi) => delegates(pi, registerChild)],
    noSkills: true,
    noPromptTemplates: true,
    noThemes: true,
    noContextFiles: true,
  });
  await loader.reload();
  const parentSettings = SettingsManager.create(workspace, agentDir, { projectTrusted: false });
  parentSession = (await createAgentSession({
    cwd: workspace,
    agentDir,
    modelRuntime: runtime,
    resourceLoader: loader,
    settingsManager: parentSettings,
    sessionManager: SessionManager.inMemory(workspace),
    model: model(PRIMARY, MODEL_ID),
    thinkingLevel: "low",
    tools: ["mapper", "librarian", "worker", "oracle", ...EXECUTOR_TOOLS],
  })).session;
  await parentSession.bindExtensions({ mode: "print" });
  assert.ok(parentContext, "parent session_start did not capture its context");
  assert.ok(parentSession, "parent session was not created");
  const parent = parentSession;
  const discoveredExtensions = path.join(isolatedSubagentResourceDir(), "extensions");
  await mkdir(discoveredExtensions, { recursive: true });
  maliciousExtension = path.join(discoveredExtensions, `malicious-${path.basename(root)}.ts`);
  await writeFile(maliciousExtension, `import { writeFileSync } from 'node:fs'; writeFileSync(${JSON.stringify(maliciousMarker)}, 'bad'); export default function () {}`);
  return {
    root,
    agentDir,
    children,
    toolSnapshots,
    maliciousMarker,
    initializationStarted,
    releaseInitialization,
    sessionClosed,
    parent,
    get initialized() { return initialized; },
    workspace,
    settingsPath: path.join(agentDir, "settings.json"),
    settings,
    calls,
    ctx: parentContext!,
    tools: new Map(["mapper", "librarian", "worker", "oracle"].map((name) => [name, parent.extensionRunner.getToolDefinition(name)!])),
    dispose: async () => {
      try {
        await shutdownAndDisposeChildSession(parent);
      } finally {
        mcpServer?.closeAllConnections();
        await new Promise<void>((resolve) => mcpServer?.close(() => resolve()) ?? resolve());
        if (maliciousExtension) await rm(maliciousExtension, { force: true });
        if (previousAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
        else process.env.PI_CODING_AGENT_DIR = previousAgentDir;
        await rm(root, { recursive: true, force: true });
      }
    },
  };
  } catch (error) {
    try {
      if (parentSession) await shutdownAndDisposeChildSession(parentSession);
      mcpServer?.closeAllConnections();
      await new Promise<void>((resolve) => mcpServer?.close(() => resolve()) ?? resolve());
      if (maliciousExtension) await rm(maliciousExtension, { force: true });
    } finally {
      if (previousAgentDir === undefined) delete process.env.PI_CODING_AGENT_DIR;
      else process.env.PI_CODING_AGENT_DIR = previousAgentDir;
      await rm(root, { recursive: true, force: true });
    }
    throw error;
  }
}

async function runTool(h: Awaited<ReturnType<typeof harness>>, name: string, params: Record<string, unknown>, updates: unknown[], signal?: AbortSignal) {
  const tool = h.tools.get(name);
  assert.ok(tool, `${name} adapter was not registered`);
  return tool.execute("integration-tool-call", params, signal, (update: unknown) => updates.push(update), h.ctx);
}

async function cleanupLibrarianWorkspace(result: any) {
  const workspace = result?.details?.agent === "librarian" ? result.details.workspace : undefined;
  if (typeof workspace === "string") await rm(workspace, { recursive: true, force: true });
}

const ADAPTERS = [
  ["mapper", { query: "fixture mapper task" }],
  ["librarian", { query: "fixture librarian task", repos: [], owners: [] }],
  ["worker", { task: "Write the fixture output and return a summary." }],
  ["oracle", { task: "Give a fixture architecture recommendation." }],
] as const;

test("runs all four real adapters through primary-to-alias failover", async () => {
  const h = await harness();
  try {
    for (const [name, params] of ADAPTERS) {
      const updates: any[] = [];
      let result: any;
      try {
        result = await runTool(h, name, params, updates);
        const expected = EXPECTED[name];
        assert.notEqual(result.isError, true, `${name} unexpectedly failed: ${JSON.stringify(result)}`);
        assert.match(result.content[0].text, new RegExp(`${name.toUpperCase()}_ALIAS_OK`));
        assert.ok(updates.some((update) => update.details?.model === `${PRIMARY}/${expected.model}`));
        assert.ok(updates.some((update) => update.details?.model === `${ALIAS}/${expected.model}`));
        const details = result.details;
        assert.equal(details.agent ?? details.delegate, name);
        assert.equal(details.model, `${ALIAS}/${expected.model}`);
        assert.equal(details.thinking, expected.thinking);
        assert.equal(details.run.status, "done");
        assert.deepEqual([...h.toolSnapshots.at(-1)!.active].sort(), [...expected.tools].sort());
        assert.deepEqual([...h.toolSnapshots.at(-1)!.callable].sort(), [...expected.tools].sort());
        if (name === "mapper") assert.equal(h.initialized, 0, "Mapper opened an MCP connection");
      } finally {
        await cleanupLibrarianWorkspace(result);
      }

      const calls = h.calls.filter((call) => call.role === name);
      assert.ok(calls.length > 0, `${name} made no provider request`);
      for (const call of calls) {
        assert.equal(call.model, EXPECTED[name].model, `${name} changed role model during failover`);
        assert.equal(call.reasoning, EXPECTED[name].thinking, `${name} changed reasoning during failover`);
        assert.deepEqual([...call.tools].sort(), [...EXPECTED[name].tools].sort(), `${name} received unrelated tools`);
      }
      assert.ok(calls.some((call) => call.provider === PRIMARY));
      assert.ok(calls.some((call) => call.provider === ALIAS));
    }

    assert.equal((await readFile(path.join(h.workspace, "worker-output.txt"), "utf8")), "written exactly once\n");
    const workerCalls = h.calls.filter((call) => call.role === "worker");
    assert.equal(workerCalls.filter((call) => call.provider === PRIMARY).length, 2, "worker primary was not resumed after its completed tool operation");
    assert.equal(workerCalls.filter((call) => call.provider === ALIAS).length, 1, "worker operation was replayed on the alias");
    const aliasWorker = workerCalls.find((call) => call.provider === ALIAS);
    assert.ok(aliasWorker, "worker alias request was not recorded");
    const writeResult = aliasWorker.context.find((message) =>
      message.role === "toolResult" && message.toolCallId === "write-once" && message.toolName === "write");
    assert.ok(writeResult, "completed worker write result was not replayed in alias context");
    assert.ok(Array.isArray(writeResult.content));
    assert.ok(writeResult.content.some((part) => part.type === "text" && /written|success/i.test(part.text)));
    assert.ok(h.calls.every((call) => !call.tools.includes("unrelated_parent_tool")));
    await assert.rejects(readFile(h.maliciousMarker), { code: "ENOENT" });
    assert.deepEqual(JSON.parse(await readFile(h.settingsPath, "utf8")), h.settings);
  } finally {
    await h.dispose();
  }
});

test("bridges legacy OAuth provider registrations into a failing-over Mapper child", async () => {
  const h = await harness("failover", "legacy");
  try {
    const updates: any[] = [];
    const result: any = await runTool(h, "mapper", { query: "fixture legacy provider task" }, updates);
    assert.notEqual(result.isError, true, JSON.stringify(result));
    assert.match(result.content[0].text, /MAPPER_ALIAS_OK/);
    assert.ok(updates.some((update) => update.details?.model === `${PRIMARY}/${MODEL_ID}`));
    assert.ok(updates.some((update) => update.details?.model === `${ALIAS}/${MODEL_ID}`));
    assert.equal(result.details.model, `${ALIAS}/${MODEL_ID}`);
    assert.deepEqual(h.calls.map((call) => call.provider), [PRIMARY, ALIAS]);
    assert.ok(h.calls.every((call) => call.role === "mapper"));
  } finally {
    await h.dispose();
  }
});

test("returns underlying failure for all four adapters when every account fails", async () => {
  const h = await harness("all-fail");
  try {
    for (const [name, params] of ADAPTERS) {
      let result: any;
      try {
        result = await runTool(h, name, params, []);
        const expectedCode = name === "librarian" ? "429" : "401";
        assert.equal(result.isError, true, `${name} did not report an error`);
        assert.match(result.content[0].text, new RegExp(`${expectedCode} fixture failure`));
        assert.doesNotMatch(result.content[0].text, /returned no final answer|no final answer/i);
        assert.doesNotMatch(result.content[0].text, new RegExp(`${name.toUpperCase()}_.*_OK`));
        assert.deepEqual(result.details.run.attemptedProviders, [PRIMARY, ALIAS]);
      } finally {
        await cleanupLibrarianWorkspace(result);
      }
    }
    assert.equal(h.calls.filter((call) => call.provider === ALIAS).length, 4);
  } finally {
    await h.dispose();
  }
});

test("does not fail over SDK aborted responses without an external signal", async () => {
  const h = await harness("aborted");
  try {
    for (const [name, params] of ADAPTERS) {
      let result: any;
      try {
        result = await runTool(h, name, params, []);
        assert.notEqual(result.isError, true, `${name} treated an abort as a provider error`);
        assert.equal(result.details.run.status, "aborted");
        assert.equal(result.details.run.terminationReason, "cancelled");
      } finally {
        await cleanupLibrarianWorkspace(result);
      }
      const calls = h.calls.filter((call) => call.role === name);
      assert.equal(calls.length, 1, `${name} switched accounts after an aborted SDK response`);
      assert.equal(calls[0].provider, PRIMARY);
      assert.equal(calls[0].model, EXPECTED[name].model);
      assert.equal(calls[0].reasoning, EXPECTED[name].thinking);
    }
  } finally {
    await h.dispose();
  }
});

async function waitUntil(predicate: () => boolean) {
  const deadline = Date.now() + 2_000;
  while (!predicate()) {
    assert.ok(Date.now() < deadline, "fixture did not reach the expected startup state");
    await new Promise<void>((resolve) => setTimeout(resolve, 10));
  }
}

test("waits for delayed native discovery before any model request", async () => {
  const h = await harness("failover", "native", "delayed");
  try {
    const running = runTool(h, "oracle", { task: "Wait for Executor tools." }, []);
    await h.initializationStarted;
    assert.equal(h.calls.length, 0);
    assert.equal(h.children.length, 1, "startup child was not registered for shutdown");
    const result: any = await running;
    assert.notEqual(result.isError, true, JSON.stringify(result));
    assert.deepEqual([...h.toolSnapshots[0]!.callable].sort(), [...EXPECTED.oracle.tools].sort());
  } finally { await h.dispose(); }
});

test("pre-aborted adapter calls never connect MCP or prompt a model", async () => {
  const h = await harness();
  try {
    const controller = new AbortController();
    controller.abort(new Error("cancelled before startup"));
    for (const [name, params] of ADAPTERS) {
      const result: any = await runTool(h, name, params, [], controller.signal);
      try { assert.equal(result.details.run.status, "aborted", JSON.stringify(result)); }
      finally { await cleanupLibrarianWorkspace(result); }
    }
    assert.equal(h.initialized, 0);
    assert.equal(h.calls.length, 0);
  } finally { await h.dispose(); }
});

test("aborting native startup prevents prompting and closes each late-completing connection", async () => {
  for (const name of ["oracle", "worker", "librarian"] as const) {
    const h = await harness("failover", "native", "hanging");
    let result: any;
    try {
      const controller = new AbortController();
      const running = runTool(h, name, name === "librarian" ? { query: "Cancel startup." } : { task: "Cancel startup." }, [], controller.signal);
      await h.initializationStarted;
      assert.equal(h.children.length, 1);
      assert.equal(h.calls.length, 0);
      controller.abort(new Error("cancelled during startup"));
      result = await running;
      assert.equal(result.details.run.status, "aborted", JSON.stringify(result));
      // Pi 1.0 owns the startup transport only after discovery. Cancellation must
      // return now; when initialization finishes, native shutdown closes it.
      h.releaseInitialization();
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        await Promise.race([h.sessionClosed, new Promise<never>((_resolve, reject) => { timer = setTimeout(() => reject(new Error("late startup connection remained open")), 2_000); })]);
      } finally { if (timer) clearTimeout(timer); }
      assert.equal(h.calls.length, 0);
      assert.equal(h.toolSnapshots.length, 0);
    } finally {
      await cleanupLibrarianWorkspace(result);
      await h.dispose();
    }
  }
});

test("parent shutdown during MCP startup prevents late model requests", async () => {
  const h = await harness("failover", "native", "hanging");
  try {
    const running = runTool(h, "oracle", { task: "Do not run after parent shutdown." }, []);
    await h.initializationStarted;
    await shutdownAndDisposeChildSession(h.parent);
    await running;
    assert.equal(h.calls.length, 0);
    h.releaseInitialization();
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([h.sessionClosed, new Promise<never>((_resolve, reject) => { timer = setTimeout(() => reject(new Error("shutdown connection remained open")), 2_000); })]);
    } finally { if (timer) clearTimeout(timer); }
    assert.equal(h.calls.length, 0);
  } finally { await h.dispose(); }
});

test("partial native tool registration cannot start a model request", async () => {
  const h = await harness("failover", "native", "partial");
  try {
    const controller = new AbortController();
    const running = runTool(h, "oracle", { task: "Do not run without resume." }, [], controller.signal);
    await waitUntil(() => h.children[0]?.getActiveToolNames().includes("mcp__executor__skills") === true);
    assert.equal(h.calls.length, 0);
    controller.abort(new Error("cancel incomplete discovery"));
    const result: any = await running;
    assert.equal(result.details.run.status, "aborted");
    assert.equal(h.calls.length, 0);
  } finally { await h.dispose(); }
});

test("native authentication failure is terminal before model or failover requests", { timeout: 20_000 }, async () => {
  const h = await harness("failover", "native", "unauthorized");
  try {
    const result: any = await runTool(h, "oracle", { task: "Never run without MCP authentication." }, []);
    assert.equal(result.isError, true, JSON.stringify(result));
    assert.equal(result.details.run.status, "error");
    assert.equal(h.calls.length, 0);
    assert.equal(h.toolSnapshots.length, 0);
  } finally { await h.dispose(); }
});

test("Worker write scope remains enforced with native MCP and account failover", async () => {
  const h = await harness();
  try {
    const allowed = path.join(h.workspace, "allowed");
    await mkdir(allowed);
    const result: any = await runTool(h, "worker", { task: "Attempt fixture write outside scope.", writeScope: [allowed] }, []);
    assert.notEqual(result.isError, true, JSON.stringify(result));
    await assert.rejects(readFile(path.join(h.workspace, "worker-output.txt")), { code: "ENOENT" });
    assert.ok(h.calls.some((call) => call.context.some((message) => message.role === "toolResult" && message.toolName === "write" && message.isError)));
    assert.deepEqual(JSON.parse(await readFile(h.settingsPath, "utf8")), h.settings);
  } finally { await h.dispose(); }
});
