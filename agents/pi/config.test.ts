import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

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

test("native MCP keeps configured servers and exposes only the three Executor entrypoints", async () => {
  const config = await jsonFile("mcp.json");
  assert.deepEqual(Object.keys(config.mcpServers).sort(), ["executor", "foilwick", "scryfall"]);
  assert.equal(config.mcpServers.executor.exposure, "hidden");
  assert.deepEqual(config.mcpServers.executor.toolExposure, { execute: "direct", skills: "direct", resume: "direct" });
});
