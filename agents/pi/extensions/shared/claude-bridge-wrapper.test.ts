import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import * as path from "node:path";
import test from "node:test";
import type { ExtensionAPI, ExtensionFactory } from "@earendil-works/pi-coding-agent";
import {
  activateClaudeBridgeFactory,
  guardClaudeBridgeProvider,
  loadClaudeBridgeFactory,
} from "../claude-bridge.ts";

test("loads a distinct bridge module factory for concurrent child sessions", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "pi-claude-wrapper-module-"));
  const entryPath = path.join(root, "bridge.mjs");
  try {
    await writeFile(entryPath, "export default function bridge() {}\n");

    const [first, second] = await Promise.all([
      loadClaudeBridgeFactory(entryPath),
      loadClaudeBridgeFactory(entryPath),
    ]);

    assert.notStrictEqual(first, second);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("invokes bridge configuration outside an untrusted project and restores cwd", async () => {
  const project = await mkdtemp(path.join(tmpdir(), "pi-claude-wrapper-project-"));
  const hostileConfig = path.join(project, ".pi", "claude-bridge.json");
  await mkdir(path.dirname(hostileConfig), { recursive: true });
  await writeFile(hostileConfig, JSON.stringify({ provider: { pathToClaudeCodeExecutable: "/tmp/hostile" } }));
  const previousCwd = process.cwd();
  let projectCwd = "";
  let observedCwd = "";
  let observedProjectConfig = true;
  const factory: ExtensionFactory = () => {
    observedCwd = process.cwd();
    observedProjectConfig = observedCwd === projectCwd;
  };

  try {
    process.chdir(project);
    projectCwd = process.cwd();
    activateClaudeBridgeFactory({} as ExtensionAPI, factory);
    assert.notEqual(observedCwd, projectCwd);
    assert.equal(observedProjectConfig, false);
    assert.equal(process.cwd(), projectCwd);
  } finally {
    process.chdir(previousCwd);
    await rm(project, { recursive: true, force: true });
  }
});

test("forces one-off summaries to use an empty trusted cwd", () => {
  let registeredConfig: Record<string, any> | undefined;
  const pi = {
    registerProvider: (_name: string, config: Record<string, any>) => {
      registeredConfig = config;
    },
  } as unknown as ExtensionAPI;
  const guarded = guardClaudeBridgeProvider(pi, "/tmp/trusted-summary-cwd");
  (guarded.registerProvider as any)("claude-bridge", {
    streamSimple: (_model: unknown, _context: unknown, options: Record<string, unknown>) => options,
  });

  const summaryOptions = registeredConfig?.streamSimple(null, null, {
    cacheRetention: "none",
    cwd: "/tmp/hostile-project",
  });
  const normalOptions = registeredConfig?.streamSimple(null, null, {
    cacheRetention: "short",
    cwd: "/tmp/real-project",
  });

  assert.equal(summaryOptions.cwd, "/tmp/trusted-summary-cwd");
  assert.equal(normalOptions.cwd, "/tmp/real-project");
});

test("rejects an asynchronous bridge factory without leaving cwd changed", async () => {
  const previousCwd = process.cwd();
  const factory: ExtensionFactory = async () => {};

  assert.throws(
    () => activateClaudeBridgeFactory({} as ExtensionAPI, factory),
    /initialize synchronously/,
  );
  assert.equal(process.cwd(), previousCwd);
});
