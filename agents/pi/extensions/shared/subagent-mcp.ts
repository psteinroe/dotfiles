import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  createMcpExtension,
  getAgentDir,
  type ExtensionAPI,
  type ExtensionContext,
  type LoadedMcpConfig,
  type LoadExtensionsResult,
  type McpServerConfig,
  type McpServerEntry,
} from "@earendil-works/pi-coding-agent";

const ISOLATED_RESOURCE_AGENT_DIR = path.join(os.tmpdir(), `pi-subagent-resources-${process.pid}`);
export const EXECUTOR_MCP_TOOLS = [
  "mcp__executor__execute",
  "mcp__executor__skills",
  "mcp__executor__resume",
] as const;
const READY_TIMEOUT_MS = 12_000;

export function isolatedSubagentResourceDir(): string {
  fs.mkdirSync(ISOLATED_RESOURCE_AGENT_DIR, { recursive: true });
  return ISOLATED_RESOURCE_AGENT_DIR;
}

type ExecutorHttpConfig = Extract<McpServerConfig, { url: string }>;

function readExecutorConfig(agentDir = getAgentDir()): { config: ExecutorHttpConfig; source: string } {
  const source = path.join(agentDir, "mcp.json");
  let parsed: unknown;
  try {
    parsed = JSON.parse(fs.readFileSync(source, "utf8"));
  } catch (error) {
    throw new Error(`Cannot read valid Executor MCP configuration at ${source}: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Executor MCP configuration must be a JSON object.");
  const servers = (parsed as Record<string, unknown>).mcpServers;
  if (!servers || typeof servers !== "object" || Array.isArray(servers)) throw new Error("Executor MCP configuration requires an mcpServers object.");
  const config = (servers as Record<string, unknown>).executor;
  if (!config || typeof config !== "object" || Array.isArray(config)) throw new Error("Executor MCP server is missing from user mcp.json.");
  const item = config as Record<string, unknown>;
  if (item.enabled !== undefined && typeof item.enabled !== "boolean") throw new Error("Executor MCP enabled must be a boolean.");
  if (item.enabled === false) throw new Error("Executor MCP server is disabled.");
  if (typeof item.url !== "string") throw new Error("Executor MCP server must use streamable HTTP.");
  let url: URL;
  try { url = new URL(item.url); } catch { throw new Error("Executor MCP server URL is invalid."); }
  const loopback = url.hostname === "localhost" || url.hostname === "127.0.0.1" || url.hostname === "[::1]";
  if (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) {
    throw new Error("Executor MCP server URL must use HTTPS (except loopback HTTP).");
  }
  if (item.type !== undefined && item.type !== "http" && item.type !== "streamable-http") throw new Error("Executor MCP server type must be HTTP.");
  if (item.headers !== undefined && (!item.headers || typeof item.headers !== "object" || Array.isArray(item.headers)
    || Object.entries(item.headers).some(([key, value]) => !/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(key) || typeof value !== "string"))) {
    throw new Error("Executor MCP headers must be string values.");
  }
  if (item.timeout !== undefined && (typeof item.timeout !== "number" || !Number.isFinite(item.timeout) || item.timeout <= 0)) throw new Error("Executor MCP timeout must be a positive number.");
  if (item.oauth !== undefined && (!item.oauth || typeof item.oauth !== "object" || Array.isArray(item.oauth))) throw new Error("Executor MCP OAuth settings must be an object.");
  const safeConfig: ExecutorHttpConfig = { url: item.url };
  if (item.headers !== undefined) safeConfig.headers = { ...(item.headers as Record<string, string>) };
  if (item.timeout !== undefined) safeConfig.timeout = item.timeout;
  if (item.oauth !== undefined) {
    const oauth = item.oauth as Record<string, unknown>;
    const stringFields = ["clientId", "clientSecret", "callbackUrl", "scope", "clientName", "authServerMetadataUrl"] as const;
    for (const key of stringFields) {
      if (oauth[key] !== undefined && typeof oauth[key] !== "string") throw new Error(`Executor MCP OAuth ${key} must be a string.`);
    }
    if (oauth.callbackPort !== undefined && (typeof oauth.callbackPort !== "number" || !Number.isInteger(oauth.callbackPort) || oauth.callbackPort < 1 || oauth.callbackPort > 65535)) {
      throw new Error("Executor MCP OAuth callbackPort must be an integer from 1 to 65535.");
    }
    const safeOAuth: Partial<NonNullable<Extract<McpServerConfig, { url: string }>["oauth"]>> = {};
    for (const key of stringFields) if (typeof oauth[key] === "string") safeOAuth[key] = oauth[key] as string;
    if (typeof oauth.callbackPort === "number") safeOAuth.callbackPort = oauth.callbackPort;
    safeConfig.oauth = safeOAuth;
  }
  return { config: safeConfig, source };
}

/** Keep native MCP tools and lifecycle handlers while hiding its interactive management command. */
export function suppressMcpCommandRegistration(api: ExtensionAPI): ExtensionAPI {
  return new Proxy(api, {
    get(target, property, receiver) {
      if (property === "registerCommand") return () => undefined;
      return Reflect.get(target, property, receiver);
    },
  });
}

export function createExecutorMcpIntegration(agentDir = getAgentDir()) {
  const loaded = readExecutorConfig(agentDir);
  const lifetime = new AbortController();
  const server: McpServerEntry = {
    name: "executor",
    source: loaded.source,
    scope: "global",
    config: {
      ...loaded.config,
      exposure: "hidden",
      toolExposure: { execute: "direct", skills: "direct", resume: "direct" },
    },
  };
  const loadConfig = (_ctx: ExtensionContext): LoadedMcpConfig => ({
    servers: [server], errors: [], autoEnableCodemode: false,
  });
  const nativeFactory = createMcpExtension({ loadConfig, startupWaitMs: 0 });
  const extensionFactory = (api: ExtensionAPI) => nativeFactory(suppressMcpCommandRegistration(api));
  const close = () => { if (!lifetime.signal.aborted) lifetime.abort(new Error("Executor MCP integration closed.")); };
  return { extensionFactory, loadConfig, close, signal: lifetime.signal, assertOpen() {
    if (lifetime.signal.aborted) throw lifetime.signal.reason instanceof Error ? lifetime.signal.reason : new Error("Executor MCP integration closed.");
  } };
}

export async function waitForExecutorTools(session: {
  getActiveToolNames(): string[];
  getCallableToolNames(): string[];
}, signal?: AbortSignal, timeoutMs = READY_TIMEOUT_MS): Promise<void> {
  const started = Date.now();
  while (true) {
    if (signal?.aborted) throw signal.reason instanceof Error ? signal.reason : new Error("Executor MCP startup aborted.");
    const active = new Set(session.getActiveToolNames());
    const callable = new Set(session.getCallableToolNames());
    if (EXECUTOR_MCP_TOOLS.every((name) => active.has(name) && callable.has(name))) return;
    if (Date.now() - started >= timeoutMs) throw new Error("Executor MCP tools did not become active and callable before the readiness deadline. Check `pi mcp list`; sign in with `pi mcp login executor` if required.");
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(done, 20);
      function done() { signal?.removeEventListener("abort", abort); resolve(); }
      function abort() { clearTimeout(timer); signal?.removeEventListener("abort", abort); reject(signal?.reason instanceof Error ? signal.reason : new Error("Executor MCP startup aborted.")); }
      signal?.addEventListener("abort", abort, { once: true });
    });
  }
}

export function isolateSubagentExtensions(allowedPaths: string[]) {
  const canonicalPaths = new Set(allowedPaths.map((extensionPath) => fs.realpathSync.native(extensionPath)));
  return (base: LoadExtensionsResult): LoadExtensionsResult => ({
    ...base,
    extensions: base.extensions.filter((extension) => {
      if (extension.path.startsWith("<inline:")) return true;
      try { return canonicalPaths.has(fs.realpathSync.native(extension.resolvedPath)); } catch { return false; }
    }),
  });
}
