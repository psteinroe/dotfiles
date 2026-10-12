import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { DELEGATE_POLICIES } from "./extensions/delegates/policy.ts";

async function jsonFile(name: string) {
  return JSON.parse(await readFile(new URL(name, import.meta.url), "utf8"));
}

test("managed settings use native MCP, no multi-account, and the pinned Claude Bridge", async () => {
  for (const name of ["settings.json", "settings.linux.json"]) {
    const settings = await jsonFile(name);
    const sources: string[] = settings.packages.map((entry: string | { source: string }) =>
      typeof entry === "string" ? entry : entry.source);
    assert.equal(settings.tuiMode, "regular");
    assert.equal(settings.extensions?.includes("-builtin:mcp") ?? false, false);
    assert.equal(sources.some((source) => source.includes("pi-mcp-adapter") || source.includes("pi-multi-account")), false);
    assert.ok(sources.includes("git:github.com/elidickinson/pi-claude-bridge@227f5eb4450a070dfbc083a7fe75b8b35366b941"));
  }
});

test("main and Worker retain Claude Bridge Opus 5.5 with high thinking on both platforms", async () => {
  for (const name of ["settings.json", "settings.linux.json"]) {
    const settings = await jsonFile(name);
    assert.equal(settings.defaultProvider, "claude-bridge");
    assert.equal(settings.defaultModel, "claude-opus-5-5");
    assert.equal(settings.enabledModels, undefined);
    assert.equal(DELEGATE_POLICIES.worker.model, `${settings.defaultProvider}/${settings.defaultModel}`);
    assert.equal(DELEGATE_POLICIES.worker.thinking, settings.defaultThinkingLevel);
  }
});

test("OpenAI is the only configured failover provider and owns model overrides", async () => {
  assert.deepEqual((await jsonFile("provider-failover.json")).providerOrder, ["openai"]);
  assert.deepEqual(Object.keys((await jsonFile("models.json")).providers), ["openai"]);
  assert.equal(DELEGATE_POLICIES.oracle.model, "openai/gpt-6-astra");
  assert.equal(DELEGATE_POLICIES.oracle.thinking, "xhigh");
  for (const role of ["finder", "librarian"]) {
    const adapter = await readFile(new URL(`extensions/${role}/adapter.ts`, import.meta.url), "utf8");
    assert.match(adapter, /MODEL_PROVIDER = "openai"|FINDER_PROVIDER = "openai"/);
  }
});

test("native MCP keeps configured servers and exposes only the three Executor entrypoints", async () => {
  const config = await jsonFile("mcp.json");
  assert.deepEqual(Object.keys(config.mcpServers).sort(), ["executor", "foilwick", "scryfall"]);
  assert.equal(config.mcpServers.executor.exposure, "hidden");
  assert.deepEqual(config.mcpServers.executor.toolExposure, { execute: "direct", skills: "direct", resume: "direct" });
});
