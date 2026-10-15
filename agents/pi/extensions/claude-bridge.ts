import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
import { randomUUID } from "node:crypto";
import {
  getAgentDir,
  type ExtensionAPI,
  type ExtensionFactory,
} from "@earendil-works/pi-coding-agent";
import { registerClaudeBridgeLogin } from "./shared/claude-bridge-login.ts";
import { prepareClaudeBridgeSource } from "./shared/claude-bridge-source.ts";
import { createClaudeUsageWait } from "./shared/claude-usage-wait-extension.ts";

const CLAUDE_BRIDGE_PROVIDER = "claude-bridge";
const BRIDGE_ENTRY_PARTS = [
  "git",
  "github.com",
  "elidickinson",
  "pi-claude-bridge",
  "src",
  "index.ts",
] as const;

export function resolveManagedClaudeBridgeEntry(agentDir = getAgentDir()): string {
  return path.join(agentDir, ...BRIDGE_ENTRY_PARTS);
}

export function guardClaudeBridgeProvider(
  pi: ExtensionAPI,
  summaryCwd: string,
  wrapStream?: ReturnType<typeof createClaudeUsageWait>,
): ExtensionAPI {
  return new Proxy(pi, {
    get(target, property, receiver) {
      if (property !== "registerProvider") {
        const value = Reflect.get(target, property, receiver);
        return typeof value === "function" ? value.bind(target) : value;
      }
      return (providerOrName: unknown, config?: Record<string, unknown>) => {
        if (
          providerOrName === CLAUDE_BRIDGE_PROVIDER
          && config
          && typeof config.streamSimple === "function"
        ) {
          const original = config.streamSimple as Parameters<ReturnType<typeof createClaudeUsageWait>>[0];
          const streamSimple = wrapStream ? wrapStream(original) : original;
          config = {
            ...config,
            streamSimple: (...args: any[]) => {
              const options = args[2] as Record<string, unknown> | undefined;
              if (options?.cacheRetention === "none") {
                args[2] = { ...options, cwd: summaryCwd };
              }
              return streamSimple(args[0], args[1], args[2]);
            },
          };
        }
        return (target.registerProvider as (...args: any[]) => unknown)(providerOrName, config);
      };
    },
  });
}

export function activateClaudeBridgeFactory(
  pi: ExtensionAPI,
  factory: ExtensionFactory,
): void {
  const safeCwd = mkdtempSync(path.join(tmpdir(), "pi-claude-bridge-config-"));
  const previousCwd = process.cwd();
  try {
    process.chdir(safeCwd);
    const result = factory(pi);
    if (result && typeof (result as Promise<void>).then === "function") {
      throw new Error("pi-claude-bridge must initialize synchronously to keep project configuration isolated");
    }
  } finally {
    process.chdir(previousCwd);
    rmSync(safeCwd, { recursive: true, force: true });
  }
}

export async function loadClaudeBridgeFactory(entryPath: string): Promise<ExtensionFactory> {
  // A unique URL gives every coordinator or child session its own bridge module
  // state, independent of Pi's process-wide extension factory cache.
  const moduleUrl = `${pathToFileURL(entryPath).href}?pi-session=${randomUUID()}`;
  const bridgeModule = await import(moduleUrl) as { default?: ExtensionFactory };
  if (typeof bridgeModule.default !== "function") {
    throw new Error(`Claude Bridge extension at ${entryPath} does not export a factory`);
  }
  return bridgeModule.default;
}

export default async function claudeBridgeProvider(pi: ExtensionAPI): Promise<void> {
  const entryPath = resolveManagedClaudeBridgeEntry();
  if (!existsSync(entryPath)) {
    throw new Error(
      `Claude Bridge extension source is unavailable at ${entryPath}. Install the configured git:github.com/elidickinson/pi-claude-bridge package before selecting a claude-bridge model.`,
    );
  }

  // Invoke the factory from an empty cwd so an untrusted project
  // .pi/claude-bridge.json cannot override the managed global policy.
  // Keep a second empty cwd for one-off summaries: bridge 0.8.0 reloads its
  // config from options.cwd on that path instead of reusing providerSettings.
  const summaryCwd = mkdtempSync(path.join(tmpdir(), "pi-claude-bridge-summary-"));
  let source: ReturnType<typeof prepareClaudeBridgeSource> | undefined;
  let initialized = false;
  try {
    source = prepareClaudeBridgeSource(entryPath);
    const wrapStream = createClaudeUsageWait(pi);
    pi.on("session_shutdown", () => {
      source?.dispose();
      rmSync(summaryCwd, { recursive: true, force: true });
    });
    activateClaudeBridgeFactory(
      guardClaudeBridgeProvider(pi, summaryCwd, wrapStream),
      await loadClaudeBridgeFactory(source.entryPath),
    );
    registerClaudeBridgeLogin(pi, { agentDir: getAgentDir(), bridgeEntry: entryPath });
    initialized = true;
  } finally {
    if (!initialized) {
      source?.dispose();
      rmSync(summaryCwd, { recursive: true, force: true });
    }
  }
}
