import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type {
  ExtensionAPI,
  LoadExtensionsResult,
} from "@earendil-works/pi-coding-agent";

const ISOLATED_RESOURCE_AGENT_DIR = path.join(
  os.tmpdir(),
  `pi-subagent-resources-${process.pid}`,
);

/** Keep global extension/package discovery out of child resource loading. */
export function isolatedSubagentResourceDir(): string {
  fs.mkdirSync(ISOLATED_RESOURCE_AGENT_DIR, { recursive: true });
  return ISOLATED_RESOURCE_AGENT_DIR;
}

/** Direct Executor tools exposed by the configured MCP adapter. */
export const EXECUTOR_MCP_TOOLS = [
  "executor_execute",
  "executor_skills",
  "executor_resume",
] as const;

/**
 * Find the already-loaded MCP adapter instead of hardcoding Pi's package cache.
 * Resolution happens when a task starts, after all parent extensions have loaded.
 */
export function resolveExecutorMcpExtensionPath(pi: Pick<ExtensionAPI, "getAllTools">): string {
  const tools = pi.getAllTools();
  const executorTools = EXECUTOR_MCP_TOOLS.map((name) => tools.find((tool) => tool.name === name));
  const missing = EXECUTOR_MCP_TOOLS.filter((_name, index) => !executorTools[index]);
  if (missing.length > 0) {
    throw new Error(
      `Executor MCP tools are unavailable: ${missing.join(", ")}. Ensure pi-mcp-adapter and the executor server are configured.`,
    );
  }

  const paths = new Set(
    executorTools
      .map((tool) => tool?.sourceInfo?.path)
      .filter((value): value is string => Boolean(value && !value.startsWith("<"))),
  );
  if (paths.size !== 1) {
    throw new Error(
      `Could not resolve one MCP adapter extension path for Executor (found ${[...paths].join(", ") || "none"}).`,
    );
  }
  const extensionPath = [...paths][0]!;
  let stat: fs.Stats;
  try {
    stat = fs.statSync(extensionPath);
  } catch {
    throw new Error(`Executor MCP adapter source is not readable: ${extensionPath}`);
  }
  if (!stat.isFile()) {
    throw new Error(`Executor MCP adapter source is not a file: ${extensionPath}`);
  }
  return extensionPath;
}

export function isolateExecutorMcpExtension(executorPath: string) {
  const canonicalPath = fs.realpathSync.native(executorPath);
  return (base: LoadExtensionsResult): LoadExtensionsResult => ({
    ...base,
    extensions: base.extensions.filter((extension) => {
      if (extension.path.startsWith("<inline:")) return true;
      try {
        return fs.realpathSync.native(extension.resolvedPath) === canonicalPath;
      } catch {
        return false;
      }
    }),
  });
}

export function assertExecutorMcpToolsRegistered(session: {
  extensionRunner: { getToolDefinition(name: string): unknown };
}): void {
  const missing = EXECUTOR_MCP_TOOLS.filter(
    (name) => !session.extensionRunner.getToolDefinition(name),
  );
  if (missing.length > 0) {
    throw new Error(`Executor MCP child tools failed to register: ${missing.join(", ")}`);
  }
}
