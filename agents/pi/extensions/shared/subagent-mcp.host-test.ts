/** Manual bundled-Pi smoke test: run with a temporary PI_CODING_AGENT_DIR.
 * pi -e <this-file> --no-extensions --no-tools --no-session --offline \
 *   --model openai-codex/native-mcp-fixture -p smoke
 * Success prints: NATIVE_MCP_HOST_OK startup-retried session-renewed isolated
 */
import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import * as path from "node:path";
import { createAssistantMessageEventStream, createProvider, type Api } from "@earendil-works/pi-ai";
import { createAgentSession, DefaultResourceLoader, getAgentDir, SessionManager, type AgentSession, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createExecutorMcpIntegration, EXECUTOR_MCP_TOOLS, waitForExecutorTools } from "./subagent-mcp.ts";
import { createSubagentModelPlan, createSubagentSettings } from "./subagent-models.ts";
import { bindAndPrepareChildSession, shutdownAndDisposeChildSession } from "./subagent-runtime.ts";

const MODEL_ID = "native-mcp-fixture";
const api = "openai-responses" as Api;

export default function nativeMcpHostTest(pi: ExtensionAPI) {
  const stream = (model: any) => {
    const result = createAssistantMessageEventStream();
    const message: any = {
      role: "assistant", content: [{ type: "text", text: "fixture" }], api, provider: model.provider, model: model.id,
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      stopReason: "stop", timestamp: Date.now(),
    };
    queueMicrotask(() => { result.push({ type: "done", reason: "stop", message }); result.end(message); });
    return result;
  };
  pi.registerProvider(createProvider({
    id: "openai-codex", name: "synthetic MCP host fixture",
    auth: { apiKey: { name: "synthetic key", resolve: async () => ({ auth: { apiKey: "fixture" }, source: "host fixture" }) } },
    models: [{ id: MODEL_ID, name: MODEL_ID, api, provider: "openai-codex", baseUrl: "http://fixture.invalid", reasoning: false,
      input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 10_000, maxTokens: 100 }],
    api: { stream, streamSimple: stream },
  }));

  pi.on("session_start", async (_event, ctx) => {
    let initializationAttempts = 0;
    let executed = 0;
    let expireSession = true;
    let child: AgentSession | undefined;
    let integration: ReturnType<typeof createExecutorMcpIntegration> | undefined;
    const server = createServer(async (request, response) => {
      if (request.method === "DELETE") { response.writeHead(204).end(); return; }
      if (request.method !== "POST") { response.writeHead(405).end(); return; }
      const chunks: Buffer[] = [];
      for await (const chunk of request) chunks.push(Buffer.from(chunk));
      let message: any;
      try { message = JSON.parse(Buffer.concat(chunks).toString("utf8")); }
      catch { response.writeHead(400).end(); return; }
      if (message.method?.startsWith("notifications/")) { response.writeHead(202).end(); return; }
      let result: any;
      if (message.method === "initialize") {
        initializationAttempts++;
        if (initializationAttempts === 1) { response.writeHead(503).end("warming up"); return; }
        result = { protocolVersion: "2025-03-26", capabilities: { tools: {} }, serverInfo: { name: "host-fixture", version: "1" } };
      } else if (message.method === "tools/list") {
        result = { tools: ["execute", "skills", "resume", "extra"].map((name) => ({ name, description: "fixture", inputSchema: { type: "object", properties: {} } })) };
      } else if (message.method === "tools/call") {
        if (expireSession) { expireSession = false; response.writeHead(404).end("expired session"); return; }
        executed++;
        result = { content: [{ type: "text", text: "NATIVE_CALL_OK" }] };
      } else { response.writeHead(400).end(); return; }
      response.writeHead(200, { "content-type": "application/json", "mcp-session-id": `host-${initializationAttempts}` })
        .end(JSON.stringify({ jsonrpc: "2.0", id: message.id, result }));
    });
    try {
      await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
      const port = (server.address() as { port: number }).port;
      const agentDir = getAgentDir();
      assert.ok(process.env.PI_CODING_AGENT_DIR && path.basename(agentDir).startsWith("pi-native-mcp-host."),
        "use a fresh /tmp/pi-native-mcp-host.XXXXXX agent directory; never run against real credentials");
      await writeFile(path.join(agentDir, "mcp.json"), JSON.stringify({ mcpServers: { executor: { url: `http://127.0.0.1:${port}/mcp` } } }));
      const plan = await createSubagentModelPlan(ctx, MODEL_ID);
      integration = createExecutorMcpIntegration(agentDir);
      const settingsManager = createSubagentSettings(ctx.cwd, agentDir);
      const resourceLoader = new DefaultResourceLoader({
        cwd: ctx.cwd, agentDir, settingsManager, noExtensions: true, noSkills: true,
        noPromptTemplates: true, noThemes: true, noContextFiles: true,
        extensionFactories: [(api) => { api.on("session_shutdown", () => integration!.close()); }, integration.extensionFactory, plan.extensionFactory],
      });
      await resourceLoader.reload();
      child = (await createAgentSession({ cwd: ctx.cwd, agentDir, settingsManager, resourceLoader,
        sessionManager: SessionManager.inMemory(ctx.cwd), model: plan.models[0], tools: [...EXECUTOR_MCP_TOOLS] })).session;
      await bindAndPrepareChildSession(child);
      await waitForExecutorTools(child, integration.signal);
      integration.assertOpen();
      assert.equal(child.extensionRunner.getCommand("mcp"), undefined);
      assert.deepEqual([...child.getCallableToolNames()].sort(), [...EXECUTOR_MCP_TOOLS].sort());
      assert.equal(initializationAttempts, 2, "bundled transport did not retry startup 503");
      const definition = child.getToolDefinition("mcp__executor__execute");
      assert.ok(definition);
      const result = await definition.execute("host-call", {}, undefined, undefined, child.extensionRunner.createContext());
      assert.ok(result.content.some((part) => part.type === "text" && part.text.includes("NATIVE_CALL_OK")), JSON.stringify(result));
      assert.equal(initializationAttempts, 3, "bundled transport did not renew expired 404 session");
      assert.equal(executed, 1, "tool operation was replayed after execution");
      console.log("NATIVE_MCP_HOST_OK startup-retried session-renewed isolated");
    } catch (error) {
      console.error(`NATIVE_MCP_HOST_ERROR ${error instanceof Error ? error.stack : String(error)}`);
    } finally {
      integration?.close();
      if (child) await shutdownAndDisposeChildSession(child);
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
      ctx.shutdown();
    }
  });
}
