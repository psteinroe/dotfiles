import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  EXECUTOR_MCP_TOOLS,
  isolateExecutorMcpExtension,
  resolveExecutorMcpExtensionPath,
} from "./subagent-mcp.ts";

function piWithTools(tools: Array<{ name: string; path: string }>) {
  return {
    getAllTools: () => tools.map((tool) => ({
      name: tool.name,
      sourceInfo: { path: tool.path },
    })),
  } as any;
}

test("resolves one readable MCP adapter path from all Executor direct tools", () => {
  const root = mkdtempSync(join(tmpdir(), "executor-mcp-source-"));
  const extensionPath = join(root, "index.ts");
  writeFileSync(extensionPath, "export default function () {}\n");
  try {
    const pi = piWithTools(EXECUTOR_MCP_TOOLS.map((name) => ({ name, path: extensionPath })));
    assert.equal(resolveExecutorMcpExtensionPath(pi), extensionPath);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("keeps only the Executor adapter and explicit inline child policies", () => {
  const root = mkdtempSync(join(tmpdir(), "executor-mcp-filter-"));
  const executorPath = join(root, "executor.ts");
  const unrelatedPath = join(root, "unrelated.ts");
  writeFileSync(executorPath, "export default function () {}\n");
  writeFileSync(unrelatedPath, "export default function () {}\n");
  try {
    const extension = (path: string, resolvedPath = path) => ({ path, resolvedPath });
    const base = {
      extensions: [
        extension(executorPath),
        extension(unrelatedPath),
        extension("<inline:1>"),
      ],
      errors: [],
      runtime: {},
    } as any;
    assert.deepEqual(
      isolateExecutorMcpExtension(executorPath)(base).extensions.map((item: any) => item.path),
      [executorPath, "<inline:1>"],
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("fails closed for missing tools, mixed sources, or unreadable source", () => {
  assert.throws(
    () => resolveExecutorMcpExtensionPath(piWithTools([
      { name: "executor_execute", path: "/adapter/index.ts" },
    ])),
    /Executor MCP tools are unavailable/,
  );
  assert.throws(
    () => resolveExecutorMcpExtensionPath(piWithTools(EXECUTOR_MCP_TOOLS.map((name, index) => ({
      name,
      path: index === 0 ? "/one/index.ts" : "/two/index.ts",
    })))),
    /Could not resolve one MCP adapter extension path/,
  );
  assert.throws(
    () => resolveExecutorMcpExtensionPath(piWithTools(
      EXECUTOR_MCP_TOOLS.map((name) => ({ name, path: "/missing/index.ts" })),
    )),
    /not readable/,
  );
});
