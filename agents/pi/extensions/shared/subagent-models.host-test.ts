/**
 * Manual Pi 0.83 host smoke test (not part of the normal test glob):
 *
 *   set -o pipefail
 *   agent_dir="$(mktemp -d)"
 *   trap 'rm -rf "$agent_dir"' EXIT
 *   PI_CODING_AGENT_DIR="$agent_dir" pi \
 *     -e agents/pi/extensions/shared/subagent-models.host-test.ts -p bridge \
 *     --no-extensions --no-tools --no-session --offline \
 *     --model openai-codex/bridge-fixture 2>&1 | tee /tmp/pi083-host-test.log || true
 *   grep -Fqx 'SUBAGENT_MODEL_BRIDGE primary-failed BRIDGE_ALIAS_OK alias-requested settings-isolated' \
 *     /tmp/pi083-host-test.log
 *
 * It registers two fake authenticated providers in the host, then creates two
 * isolated children from the model plan. The primary deterministically fails;
 * the bridged account alias succeeds without loading the host extension set.
 */
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import {
  createAssistantMessageEventStream,
  createProvider,
  type Api,
  type AssistantMessageEventStream,
  type Context,
  type Model,
} from "@earendil-works/pi-ai";
import {
  createAgentSession,
  DefaultResourceLoader,
  SessionManager,
  type ExtensionAPI,
  type ExtensionContext,
  type ExtensionFactory,
} from "@earendil-works/pi-coding-agent";
import { createSubagentModelPlan, createSubagentSettings } from "./subagent-models.ts";

const MODEL_ID = "bridge-fixture";
const API = "openai-responses" as Api;
const calls: Array<{ provider: string; model: string; reasoning: unknown }> = [];

const modelConfig = (provider: string, id: string) => ({
  id,
  name: `${provider}/${id}`,
  api: API,
  provider,
  baseUrl: "http://fixture.invalid",
  reasoning: true,
  thinkingLevelMap: {
    off: "off",
    minimal: "minimal",
    low: "low",
    medium: "medium",
    high: "high",
  },
  input: ["text"] as ("text" | "image")[],
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  contextWindow: 10_000,
  maxTokens: 100,
});

function nativeFixtureProvider(id: string, succeeds: boolean) {
  const stream = (model: Model<Api>, _context: Context, options?: any) => {
    calls.push({ provider: model.provider, model: model.id, reasoning: options?.reasoning });
    return resultStream(model, succeeds);
  };
  return createProvider({
    id,
    name: id,
    auth: {
      apiKey: {
        name: "temporary bridge fixture key",
        // This is deliberately synthetic and side-effect free: neither the
        // parent nor child can read or write a real auth.json.
        resolve: async () => ({
          auth: { apiKey: `fixture-${id}-key` },
          source: "temporary bridge fixture",
        }),
      },
    },
    models: [modelConfig(id, MODEL_ID)],
    api: { stream, streamSimple: stream },
  });
}

function resultStream(model: Model<Api>, succeeds: boolean): AssistantMessageEventStream {
  const stream = createAssistantMessageEventStream();
  const message = {
    role: "assistant" as const,
    content: [{ type: "text" as const, text: succeeds ? "BRIDGE_ALIAS_OK" : "" }],
    api: model.api,
    provider: model.provider,
    model: model.id,
    usage: {
      input: 1,
      output: succeeds ? 1 : 0,
      cacheRead: 0,
      cacheWrite: 0,
      totalTokens: succeeds ? 2 : 1,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
    },
    stopReason: succeeds ? ("stop" as const) : ("error" as const),
    ...(succeeds ? {} : { errorMessage: "primary fixture failure" }),
    timestamp: Date.now(),
  };
  queueMicrotask(() => {
    if (succeeds) {
      stream.push({ type: "done", reason: "stop", message });
      stream.end(message);
    } else {
      stream.push({ type: "error", reason: "error", error: message });
      stream.end(message);
    }
  });
  return stream;
}

async function childFactory(
  cwd: string,
  agentDir: string,
  extensionFactory: ExtensionFactory,
  model: Model<Api>,
  thinkingLevel: "low" | "high",
) {
  const settingsManager = createSubagentSettings(cwd, agentDir);
  const resourceLoader = new DefaultResourceLoader({
    cwd,
    agentDir,
    settingsManager,
    noExtensions: true,
    noSkills: true,
    noPromptTemplates: true,
    noThemes: true,
    noContextFiles: true,
    extensionFactories: [extensionFactory],
  });
  await resourceLoader.reload();
  const child = await createAgentSession({
    cwd,
    agentDir,
    resourceLoader,
    settingsManager,
    sessionManager: SessionManager.inMemory(cwd),
    model,
    thinkingLevel,
    noTools: "all",
  });
  try {
    await child.session.bindExtensions({ mode: "print" });
    return child;
  } catch (error) {
    child.session.dispose();
    throw error;
  }
}

export default function hostSmokeTest(pi: ExtensionAPI) {
  // Register effective native providers, not legacy `$ENV` configs: children
  // have a separate auth store and must receive the provider's auth behavior.
  pi.registerProvider(nativeFixtureProvider("openai-codex", false));
  pi.registerProvider(nativeFixtureProvider("openai-codex-account-1", true));

  pi.on("session_start", async (_event, ctx: ExtensionContext) => {
    const root = await mkdtemp(path.join(tmpdir(), "pi-model-bridge-host-"));
    const agentDir = path.join(root, "agent");
    await mkdir(agentDir, { recursive: true });
    const parentSettings = {
      defaultProvider: "openai-codex",
      defaultModel: "parent-model",
      defaultThinkingLevel: "low",
      theme: "parent-theme",
    };
    await writeFile(path.join(agentDir, "settings.json"), JSON.stringify(parentSettings));
    // Keep the child credential file temporary too; this guards the host
    // compatibility path that asks its credential store before native auth.
    await writeFile(path.join(agentDir, "auth.json"), JSON.stringify({
      "openai-codex": { type: "api_key", key: "fake-primary-key" },
      "openai-codex-account-1": { type: "api_key", key: "fake-alias-key" },
    }));
    try {
      // Allow the synchronous facade to observe the initial registration.
      await new Promise<void>((resolve) => setImmediate(resolve));
      const plan = await createSubagentModelPlan(ctx, MODEL_ID);
      if (plan.models.map((model) => model.provider).join(",") !== "openai-codex,openai-codex-account-1") {
        throw new Error("native provider plan did not preserve base/alias order");
      }
      let primary: Awaited<ReturnType<typeof childFactory>> | undefined;
      let primaryFailed = false;
      try {
        primary = await childFactory(ctx.cwd, agentDir, plan.extensionFactory, plan.models[0], "low");
        try {
          await primary.session.prompt("Say exactly one word.");
          primaryFailed = primary.session.messages.some(
            (message) => message.role === "assistant" && message.stopReason === "error",
          );
        } catch {
          primaryFailed = true;
        }
      } finally {
        primary?.session.dispose();
      }

      let answer: string | undefined;
      let alias: Awaited<ReturnType<typeof childFactory>> | undefined;
      try {
        alias = await childFactory(ctx.cwd, agentDir, plan.extensionFactory, plan.models[1], "high");
        if (alias.session.model?.provider !== "openai-codex-account-1" || alias.session.thinkingLevel !== "high") {
          throw new Error("alias child did not select its role model/thinking level");
        }
        await alias.session.prompt("Say exactly one word.");
        answer = alias.session.messages
          .filter((message) => message.role === "assistant")
          .flatMap((message) => message.content)
          .find((part) => part.type === "text")?.text;
      } finally {
        alias?.session.dispose();
      }
      if (JSON.stringify(JSON.parse(await readFile(path.join(agentDir, "settings.json"), "utf8"))) !== JSON.stringify(parentSettings)) {
        throw new Error("child changed parent settings");
      }
      const aliasCall = calls.find((call) => call.provider === "openai-codex-account-1");
      if (!aliasCall || aliasCall.model !== MODEL_ID || aliasCall.reasoning !== "high") {
        throw new Error("native alias provider did not receive the alias request/thinking level");
      }
      console.log(`SUBAGENT_MODEL_BRIDGE ${primaryFailed ? "primary-failed" : "primary-did-not-fail"} ${answer ?? "no-answer"} alias-requested settings-isolated`);
    } catch (error) {
      console.error(`SUBAGENT_MODEL_BRIDGE_ERROR ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      await rm(root, { recursive: true, force: true });
      ctx.shutdown();
    }
  });
}
