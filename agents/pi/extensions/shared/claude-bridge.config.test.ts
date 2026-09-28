import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import * as path from "node:path";
import test from "node:test";

interface BridgeConfig {
  askClaude?: { enabled?: boolean; allowFullMode?: boolean };
  provider?: {
    plan?: string;
    autoMemoryEnabled?: boolean;
    longContextExtraUsage?: boolean;
    strictMcpConfig?: boolean;
  };
}

test("managed Claude bridge config keeps provider-only Max mode isolated and unmetered", async () => {
  const configPath = path.resolve(import.meta.dirname, "../..", "claude-bridge.json");
  const config = JSON.parse(await readFile(configPath, "utf8")) as BridgeConfig;

  assert.equal(config.provider?.plan, "max");
  assert.equal(config.provider?.longContextExtraUsage, false);
  assert.equal(config.provider?.autoMemoryEnabled, false);
  assert.equal(config.provider?.strictMcpConfig, true);
  assert.equal(config.askClaude?.enabled, false);
  assert.equal(config.askClaude?.allowFullMode, false);
});

test("installs the pinned bridge package without auto-loading its unguarded entrypoint", async () => {
  const source = "git:github.com/elidickinson/pi-claude-bridge@227f5eb4450a070dfbc083a7fe75b8b35366b941";
  for (const file of ["settings.json", "settings.linux.json"]) {
    const settingsPath = path.resolve(import.meta.dirname, "../..", file);
    const settings = JSON.parse(await readFile(settingsPath, "utf8")) as {
      packages?: Array<string | { source?: string; extensions?: string[] }>;
    };
    const bridge = settings.packages?.find(
      (entry) => typeof entry === "object" && entry.source === source,
    );
    assert.deepEqual(bridge, {
      source,
      extensions: [],
    });
  }
});
