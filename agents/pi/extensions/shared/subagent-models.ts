import {
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
const ACCOUNT_PROVIDER = /^openai-codex-account-(\d+)$/u;

function providerOrder(provider: string): [number, number, string] | undefined {
  if (provider === BASE_PROVIDER) return [0, 0, provider];
  const account = ACCOUNT_PROVIDER.exec(provider);
  if (!account) return undefined;
  return [1, Number(account[1]), provider];
}

/**
 * Select exactly one authenticated model per registered provider and bridge the
 * corresponding native providers into a fresh child runtime.
 *
 * `getAvailable()` is intentionally the auth eligibility check. In Pi 0.83 it
 * is a synchronous snapshot; the async function is kept for the helper's
 * session-building API and does not perform credential reads here.
 */
export async function createSubagentModelPlan(
  ctx: Pick<ExtensionContext, "modelRegistry">,
  modelId: string,
): Promise<{ models: Model[]; extensionFactory: ExtensionFactory }> {
  const byProvider = new Map<string, Model>();

  for (const model of ctx.modelRegistry.getAvailable()) {
    if (model.id !== modelId || byProvider.has(model.provider)) continue;
    if (providerOrder(model.provider) === undefined) continue;
    byProvider.set(model.provider, model);
  }

  const ordered = [...byProvider.entries()].sort((a, b) => {
    const left = providerOrder(a[0])!;
    const right = providerOrder(b[0])!;
    return left[0] - right[0] || left[1] - right[1] || left[2].localeCompare(right[2]);
  });

  const providers: NativeProvider[] = [];
  const models: Model[] = [];
  for (const [providerId, model] of ordered) {
    const provider = ctx.modelRegistry.getProvider(providerId);
    // A stale availability snapshot must not make an unusable bridge.
    if (!provider) continue;
    providers.push(provider);
    models.push(model);
  }

  if (models.length === 0) {
    throw new Error(
      `No authenticated candidate provider is available for model "${modelId}" `
      + `(checked ${BASE_PROVIDER} and ${BASE_PROVIDER}-account-N providers).`,
    );
  }

  const extensionFactory: ExtensionFactory = (pi) => {
    for (const provider of providers) pi.registerProvider(provider);
  };
  return { models, extensionFactory };
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
