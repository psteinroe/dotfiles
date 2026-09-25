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

const BASE_PROVIDER = "openai-codex";
const CLAUDE_BRIDGE_PROVIDER = "claude-bridge";
const ACCOUNT_PROVIDER = /^openai-codex-account-(\d+)$/u;
const CLAUDE_BRIDGE_WRAPPER = ["extensions", "claude-bridge.ts"] as const;
const CLAUDE_BRIDGE_PACKAGE_ENTRY = [
  "npm",
  "node_modules",
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
  // Codex role defaults. Public overrides call parseExactSubagentModelRef().
  if (separator < 0) return { provider: BASE_PROVIDER, modelId: normalized };
  const exact = parseExactSubagentModelRef(normalized);
  const exactSeparator = exact.indexOf("/");
  return {
    provider: exact.slice(0, exactSeparator),
    modelId: exact.slice(exactSeparator + 1),
  };
}

function providerOrder(provider: string): [number, number, string] | undefined {
  if (provider === BASE_PROVIDER) return [0, 0, provider];
  const account = ACCOUNT_PROVIDER.exec(provider);
  if (!account) return undefined;
  return [1, Number(account[1]), provider];
}

/**
 * Select authenticated models for an exact provider/model reference. The base
 * Codex provider retains numeric account failover; every other provider is a
 * single exact candidate.
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
    const matches = selection.provider === BASE_PROVIDER
      ? providerOrder(model.provider) !== undefined
      : model.provider === selection.provider;
    if (matches) byProvider.set(model.provider, model);
  }

  const ordered = [...byProvider.entries()].sort((a, b) => {
    if (selection.provider !== BASE_PROVIDER) return a[0].localeCompare(b[0]);
    const left = providerOrder(a[0])!;
    const right = providerOrder(b[0])!;
    return left[0] - right[0] || left[1] - right[1] || left[2].localeCompare(right[2]);
  });

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
    const checked = selection.provider === BASE_PROVIDER
      ? `${BASE_PROVIDER} and ${BASE_PROVIDER}-account-N providers`
      : `${selection.provider}`;
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
    + "Deploy the managed extension and install npm:pi-claude-bridge@0.8.0 before selecting a claude-bridge model.",
  );
}

/**
 * Snapshot the untrusted parent settings into an in-memory manager. Children
 * may change their model/thinking settings without writing parent defaults.
 * Keep the parent's global configuration, but let the bounded failover layer
 * own retries rather than competing with SDK and provider retries.
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
  settings.retry = {
    ...settings.retry,
    enabled: false,
    provider: {
      ...settings.retry?.provider,
      maxRetries: 0,
    },
  };
  return SettingsManager.inMemory(settings, { projectTrusted: false });
}
