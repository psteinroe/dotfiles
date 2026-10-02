import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createExecutorMcpIntegration, EXECUTOR_MCP_TOOLS, waitForExecutorTools } from "./subagent-mcp.ts";

function config(dir: string, value: unknown) {
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "mcp.json"), JSON.stringify(value));
}

test("loads only user Executor HTTP settings and replaces exposure with the exact allowlist", async () => {
  const dir = mkdtempSync(join(tmpdir(), "executor-native-config-"));
  try {
    config(dir, { mcpServers: { executor: { url: "https://executor.example/mcp", headers: { Authorization: "Bearer test" }, exposure: "direct", toolExposure: { "*": "direct" }, directTools: ["danger"], resourcesExposure: "direct", unknown: true }, other: { command: "must-not-load" } } });
    const integration = createExecutorMcpIntegration(dir);
    const loaded = integration.loadConfig({} as any);
    assert.equal(loaded.servers.length, 1);
    assert.equal(loaded.servers[0]?.name, "executor");
    assert.equal(loaded.servers[0]?.source, join(dir, "mcp.json"));
    assert.deepEqual(loaded.servers[0]?.config.toolExposure, { execute: "direct", skills: "direct", resume: "direct" });
    assert.equal(loaded.servers[0]?.config.exposure, "hidden");
    assert.equal("directTools" in loaded.servers[0]!.config, false);
    assert.equal("unknown" in loaded.servers[0]!.config, false);
    assert.equal("resourcesExposure" in loaded.servers[0]!.config, false);
    assert.deepEqual(loaded.errors, []);
    assert.equal(loaded.autoEnableCodemode, false);
    await integration.close();
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("rejects malformed, missing, disabled, stdio, and unsafe HTTP configuration", () => {
  const dir = mkdtempSync(join(tmpdir(), "executor-native-invalid-"));
  try {
    for (const value of [null, {}, { mcpServers: {} }, { mcpServers: { executor: { url: "https://x", enabled: false } } }, { mcpServers: { executor: { command: "unsafe" } } }, { mcpServers: { executor: { url: "http://remote/mcp" } } }, { mcpServers: { executor: { url: "ftp://localhost/mcp" } } }, { mcpServers: { executor: { url: "file://localhost/mcp" } } }, { mcpServers: { executor: { url: "https://x", oauth: { callbackPort: "8000" } } } }]) {
      config(dir, value);
      assert.throws(() => createExecutorMcpIntegration(dir));
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("close aborts lifetime synchronously and readiness fails closed before and after tools appear", async () => {
  const dir = mkdtempSync(join(tmpdir(), "executor-native-lifetime-"));
  try {
    config(dir, { mcpServers: { executor: { url: "https://executor.example/mcp" } } });
    const integration = createExecutorMcpIntegration(dir);
    const session = { getActiveToolNames: () => [...EXECUTOR_MCP_TOOLS], getCallableToolNames: () => [...EXECUTOR_MCP_TOOLS] };
    await waitForExecutorTools(session, integration.signal);
    integration.close();
    assert.equal(integration.signal.aborted, true);
    assert.throws(() => integration.assertOpen(), /closed/);
    await assert.rejects(waitForExecutorTools(session, integration.signal), /closed/);

    const second = createExecutorMcpIntegration(dir);
    const inactive = { getActiveToolNames: () => [], getCallableToolNames: () => [] };
    const waiting = waitForExecutorTools(inactive, second.signal, 2_000);
    second.close();
    await assert.rejects(waiting, /closed/);
    const preAborted = new AbortController();
    preAborted.abort(new Error("parent already shut down"));
    await assert.rejects(waitForExecutorTools(session, preAborted.signal), /parent already shut down/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("native MCP factory cannot register the logout-capable /mcp command", () => {
  const dir = mkdtempSync(join(tmpdir(), "executor-native-command-"));
  try {
    config(dir, { mcpServers: { executor: { url: "https://executor.example/mcp" } } });
    let commandRegistrations = 0;
    const api = new Proxy({} as any, { get(_target, property) {
      if (property === "registerCommand") return () => { commandRegistrations++; };
      if (property === "on") return () => () => undefined;
      return () => undefined;
    } });
    createExecutorMcpIntegration(dir).extensionFactory(api);
    assert.equal(commandRegistrations, 0, "headless callers must not expose /mcp logout");
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("waits for all exact active callable tools and honors abort/deadline", async () => {
  const active = new Set<string>();
  const session = { getActiveToolNames: () => [...active], getCallableToolNames: () => [...active] };
  const waiting = waitForExecutorTools(session, undefined, 1_000);
  setTimeout(() => EXECUTOR_MCP_TOOLS.forEach((name) => active.add(name)), 30);
  await waiting;
  active.delete(EXECUTOR_MCP_TOOLS[2]!);
  await assert.rejects(waitForExecutorTools(session, undefined, 40), /readiness deadline/);
  const controller = new AbortController();
  const aborted = waitForExecutorTools(session, controller.signal, 1_000);
  controller.abort(new Error("task cancelled"));
  await assert.rejects(aborted, /task cancelled/);
});
