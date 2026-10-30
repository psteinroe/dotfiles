import * as fs from "node:fs";
import * as path from "node:path";
import {
  getAgentDir,
  SettingsManager,
  type ExtensionContext,
  type ExtensionFactory,
} from "@earendil-works/pi-coding-agent";

/** A model as exposed by the 0.83 model-registry facade. */
export type Model = ReturnType<
  ExtensionContext["modelRegistry"]["getAvailable"]
>[number];

type NativeProvider = NonNullable<
  ReturnType<ExtensionContext["modelRegistry"]["getProvider"]>
>;

const BASE_PROVIDER = "openai";
const CLAUDE_BRIDGE_PROVIDER = "claude-bridge";
const CLAUDE_BRIDGE_WRAPPER = ["extensions", "claude-bridge.ts"] as const;
const CLAUDE_BRIDGE_PACKAGE_ENTRY = [
  "git",
  "github.com",
  "elidickinson",
  "pi-claude-bridge",
  "src",
  "index.ts",
] as const;

export interface SubagentModelPlan {
  models: Model[];
  extensionFactory: ExtensionFactory;
  requiresClaudeBridge: boolean;
}

export function parseExactSubagentModelRef(modelRef: string): string {
  const normalized = modelRef.trim();
  const separator = normalized.indexOf("/");
  const provider = normalized.slice(0, separator);
  const modelId = normalized.slice(separator + 1);
  if (separator <= 0 || !modelId || /\s/u.test(normalized)) {
    throw new Error(`Invalid subagent model "${modelRef}"; expected an exact provider/model reference.`);
  }
  return normalized;
}

function parseModelRef(modelRef: string): { provider: string; modelId: string } {
  const normalized = modelRef.trim();
  const separator = normalized.indexOf("/");
  // Keep bare IDs only as an internal compatibility shorthand for existing
  // OpenAI role defaults. Public overrides call parseExactSubagentModelRef().
  if (separator < 0) return { provider: BASE_PROVIDER, modelId: normalized };
  const exact = parseExactSubagentModelRef(normalized);
  const exactSeparator = exact.indexOf("/");
  return {
    provider: exact.slice(0, exactSeparator),
    modelId: exact.slice(exactSeparator + 1),
  };
}

/**
 * Select one authenticated model for the requested provider. Account routing
 * belongs to the server, never to a child session.
 *
 * Claude Bridge is deliberately not copied as a provider object. Its provider
 * depends on prompt-capture, compaction, session-sync, and shutdown hooks, so a
 * fresh child must load the complete extension lifecycle instead.
 */
export async function createSubagentModelPlan(
  ctx: Pick<ExtensionContext, "modelRegistry">,
  modelRef: string,
): Promise<SubagentModelPlan> {
  const selection = parseModelRef(modelRef);
  if (!selection.modelId) {
    throw new Error(`Invalid subagent model "${modelRef}"; expected an exact provider/model reference.`);
  }

  const byProvider = new Map<string, Model>();
  for (const model of ctx.modelRegistry.getAvailable()) {
    if (model.id !== selection.modelId || byProvider.has(model.provider)) continue;
    if (model.provider === selection.provider) byProvider.set(model.provider, model);
  }

  const ordered = [...byProvider.entries()];

  const providers: NativeProvider[] = [];
  const models: Model[] = [];
  for (const [providerId, model] of ordered) {
    const provider = ctx.modelRegistry.getProvider(providerId);
    // A stale availability snapshot must not make an unusable child.
    if (!provider) continue;
    if (selection.provider !== CLAUDE_BRIDGE_PROVIDER) providers.push(provider);
    models.push(model);
  }

  if (models.length === 0) {
    const checked = selection.provider;
    throw new Error(
      `No authenticated candidate provider is available for model "${selection.provider}/${selection.modelId}" `
      + `(checked ${checked}).`,
    );
  }

  const extensionFactory: ExtensionFactory = (pi) => {
    for (const provider of providers) pi.registerProvider(provider);
  };
  return {
    models,
    extensionFactory,
    requiresClaudeBridge: selection.provider === CLAUDE_BRIDGE_PROVIDER,
  };
}

/** Reload the isolated child resources once. The managed Claude wrapper imports
 * the bridge entrypoint through a unique URL, so it does not depend on Pi's
 * process-wide extension factory cache for module-state isolation. */
export async function reloadSubagentResources(loader: { reload(): Promise<void> }): Promise<void> {
  await loader.reload();
}

/** Resolve the reviewed managed wrapper needed by Claude-backed children. */
export function resolveSubagentLifecycleExtensionPaths(
  plan: Pick<SubagentModelPlan, "requiresClaudeBridge">,
  agentDir = getAgentDir(),
): string[] {
  if (!plan.requiresClaudeBridge) return [];
  const wrapperPath = path.join(agentDir, ...CLAUDE_BRIDGE_WRAPPER);
  const packageEntry = path.join(agentDir, ...CLAUDE_BRIDGE_PACKAGE_ENTRY);
  try {
    const resolvedWrapper = fs.realpathSync.native(wrapperPath);
    const resolvedPackage = fs.realpathSync.native(packageEntry);
    if (fs.statSync(resolvedWrapper).isFile() && fs.statSync(resolvedPackage).isFile()) {
      return [resolvedWrapper];
    }
  } catch {
    // Use one actionable error below for missing, unreadable, or invalid paths.
  }
  throw new Error(
    `Claude Bridge managed wrapper or package source is unavailable (${wrapperPath}, ${packageEntry}). `
    + "Deploy the managed extension and install git:github.com/elidickinson/pi-claude-bridge before selecting a claude-bridge model.",
  );
}

/**
 * Snapshot the untrusted parent settings into an in-memory manager. Children
 * may change their model/thinking settings without writing parent defaults.
 * Keep global configuration and use Pi's normal retry policy.
 */
export function createSubagentSettings(cwd: string, agentDir: string): SettingsManager {
  const parentSettings = SettingsManager.create(cwd, agentDir, {
    projectTrusted: false,
  });
  const settings = parentSettings.getGlobalSettings();
  // Child resources are installed explicitly. Do not rediscover parent package
  // extensions or configured extension paths inside each background agent.
  settings.packages = [];
  settings.extensions = [];
  delete settings.retry;
  return SettingsManager.inMemory(settings, { projectTrusted: false });
}
