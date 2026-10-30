import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import test from "node:test";
import { createAssistantMessageEventStream, createProvider } from "@earendil-works/pi-ai";
import { SettingsManager, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  createSubagentModelPlan,
  createSubagentSettings,
  parseExactSubagentModelRef,
  reloadSubagentResources,
  resolveSubagentLifecycleExtensionPaths,
  type Model,
} from "./subagent-models.ts";

type Registry = Pick<ExtensionContext, "modelRegistry">["modelRegistry"];
type Provider = NonNullable<ReturnType<Registry["getProvider"]>>;

function model(provider: string, id = "gpt-fixture"): Model {
  return {
    id,
    name: `${provider}/${id}`,
    api: "openai-responses",
    provider,
    baseUrl: "https://fixture.invalid",
    reasoning: false,
    input: ["text"],
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    contextWindow: 1000,
    maxTokens: 100,
  } as Model;
}

function provider(id: string): Provider {
  return { id, name: id, getModels: () => [] } as unknown as Provider;
}

function nativeProvider(id: string): Provider {
  return createProvider({
    id,
    name: id,
    auth: {
      apiKey: {
        name: "test-only synthetic key",
        resolve: async () => ({ auth: { apiKey: `synthetic-${id}` }, source: "test fixture" }),
      },
    },
    models: [model(id)],
    api: {
      stream: () => createAssistantMessageEventStream(),
      streamSimple: () => createAssistantMessageEventStream(),
    },
  });
}

function registry(available: Model[], providers: Map<string, Provider>): Registry {
  return {
    getAvailable: () => available,
    getProvider: (id: string) => providers.get(id),
  } as unknown as Registry;
}

test("selects only the requested provider, ignoring local account aliases", async () => {
  const available = [
    model("unrelated"),
    model("openai-account-10"),
    model("openai-account-2"),
    model("openai"),
    model("openai-account-1"),
    model("openai", "other-model"),
    model("openai-account-2"),
  ];
  const providers = new Map(
    ["openai", "openai-account-1", "openai-account-2", "openai-account-10"]
      .map((id) => [id, provider(id)] as const),
  );
  const plan = await createSubagentModelPlan({ modelRegistry: registry(available, providers) }, "gpt-fixture");

  assert.deepEqual(
    plan.models.map((candidate) => candidate.provider),
    ["openai"],
  );

  const registered: Provider[] = [];
  plan.extensionFactory({
    registerProvider: (nativeProvider: Provider) => registered.push(nativeProvider),
  } as unknown as ExtensionAPI);
  assert.deepEqual(registered.map((candidate) => candidate.id), ["openai"]);
});

test("bridges effective native parent provider authentication", async () => {
  const base = nativeProvider("openai");
  const alias = nativeProvider("openai-account-1");
  const providers = new Map([[base.id, base], [alias.id, alias]]);
  const available = [...base.getModels(), ...alias.getModels()];
  const plan = await createSubagentModelPlan({ modelRegistry: registry(available, providers) }, "gpt-fixture");
  const childProviders = new Map<string, Provider>();
  plan.extensionFactory({
    registerProvider: (candidate: Provider) => childProviders.set(candidate.id, candidate),
  } as unknown as ExtensionAPI);

  assert.strictEqual(childProviders.get(base.id), base);
  assert.equal(childProviders.has(alias.id), false);
  const auth = await base.auth.apiKey?.resolve({
    ctx: { env: async () => undefined, fileExists: async () => false },
    signal: AbortSignal.timeout(1_000),
  });
  assert.deepEqual(auth?.auth.apiKey, "synthetic-openai");
});

test("OpenAI plans never fall back to Codex accounts", async () => {
  const openai = nativeProvider("openai");
  const codex = nativeProvider("openai-codex");
  const codexAlias = nativeProvider("openai-codex-account-2");
  const providers = new Map([openai, codex, codexAlias].map((candidate) => [candidate.id, candidate]));
  const available = [...openai.getModels(), ...codex.getModels(), ...codexAlias.getModels()];
  const plan = await createSubagentModelPlan({ modelRegistry: registry(available, providers) }, "openai/gpt-fixture");
  assert.deepEqual(plan.models.map((candidate) => candidate.provider), ["openai"]);
  assert.equal(plan.requiresClaudeBridge, false);
  await assert.rejects(createSubagentModelPlan({
    modelRegistry: registry([...codex.getModels(), ...codexAlias.getModels()], providers),
  }, "gpt-fixture"), /No authenticated candidate provider/);
});

test("selects Claude exactly and loads its complete child lifecycle instead of copying the provider", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "pi-claude-bridge-plan-"));
  const packageEntry = path.join(
    root,
    "git",
    "github.com",
    "elidickinson",
    "pi-claude-bridge",
    "src",
    "index.ts",
  );
  const wrapperPath = path.join(root, "extensions", "claude-bridge.ts");
  try {
    await mkdir(path.dirname(packageEntry), { recursive: true });
    await mkdir(path.dirname(wrapperPath), { recursive: true });
    await writeFile(packageEntry, "export default () => {};\n");
    await writeFile(wrapperPath, "export default () => {};\n");
    const claude = provider("claude-bridge");
    const plan = await createSubagentModelPlan({
      modelRegistry: registry(
        [model("claude-bridge", "claude-opus-4-6"), model("openai", "claude-opus-4-6")],
        new Map([[claude.id, claude]]),
      ),
    }, "claude-bridge/claude-opus-4-6");

    assert.deepEqual(plan.models.map((candidate) => candidate.provider), ["claude-bridge"]);
    assert.equal(plan.requiresClaudeBridge, true);
    const registered: Provider[] = [];
    plan.extensionFactory({
      registerProvider: (candidate: Provider) => registered.push(candidate),
    } as unknown as ExtensionAPI);
    assert.deepEqual(registered, []);
    assert.deepEqual(resolveSubagentLifecycleExtensionPaths(plan, root), [await realpath(wrapperPath)]);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("loads isolated resources once because the managed wrapper imports a fresh bridge module", async () => {
  let reloads = 0;
  const loader = { reload: async () => { reloads += 1; } };

  await reloadSubagentResources(loader);

  assert.equal(reloads, 1);
});

test("model reference parser requires a non-empty exact provider/model reference", () => {
  assert.equal(
    parseExactSubagentModelRef(" claude-bridge/claude-opus-4-6 "),
    "claude-bridge/claude-opus-4-6",
  );
  for (const invalid of ["", "   ", "claude-opus-4-6", "provider/", "/model", "provider /model"]) {
    assert.throws(() => parseExactSubagentModelRef(invalid), /exact provider\/model reference/);
  }
});

test("an account alias cannot silently replace an unavailable requested provider", async () => {
  const alias = provider("openai-account-3");
  await assert.rejects(createSubagentModelPlan({
    modelRegistry: registry([model(alias.id)], new Map([[alias.id, alias]])),
  }, "gpt-fixture"), /No authenticated candidate provider/);
});

test("unavailable models and non-account providers are not candidates", async () => {
  await assert.rejects(
    createSubagentModelPlan({
      modelRegistry: registry(
        [model("openai", "different-model"), model("openai-account-x")],
        new Map(),
      ),
    }, "gpt-fixture"),
    /No authenticated candidate provider.*gpt-fixture/,
  );
});

test("settings are copied from untrusted global settings and never persisted", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "pi-subagent-settings-"));
  const cwd = path.join(root, "project");
  const agentDir = path.join(root, "agent");
  try {
    await mkdir(cwd, { recursive: true });
    await mkdir(agentDir, { recursive: true });
    const original = {
      defaultProvider: "openai",
      defaultModel: "parent-model",
      theme: "parent-theme",
      retry: { enabled: true, maxRetries: 7, provider: { maxRetries: 5, timeoutMs: 1234 } },
    };
    await writeFile(path.join(agentDir, "settings.json"), JSON.stringify(original));
    await writeFile(path.join(cwd, ".pi-settings-sentinel"), "not used");

    const settings = createSubagentSettings(cwd, agentDir);
    assert.equal(settings.isProjectTrusted(), false);
    assert.equal(settings.getDefaultModel(), "parent-model");
    assert.equal(settings.getTheme(), "parent-theme");
    const defaults = SettingsManager.inMemory({});
    assert.deepEqual(settings.getRetrySettings(), defaults.getRetrySettings());
    assert.deepEqual(settings.getProviderRetrySettings(), defaults.getProviderRetrySettings());

    settings.setDefaultModel("child-model");
    settings.setDefaultThinkingLevel("high");
    await settings.flush();
    assert.deepEqual(JSON.parse(await readFile(path.join(agentDir, "settings.json"), "utf8")), original);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
