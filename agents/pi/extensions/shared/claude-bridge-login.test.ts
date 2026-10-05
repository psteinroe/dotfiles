import assert from "node:assert/strict";
import test from "node:test";
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { registerClaudeBridgeLogin, resolveClaudeLoginCli } from "./claude-bridge-login.ts";

const paths = { agentDir: "/trusted/agent", bridgeEntry: "/trusted/bridge/src/index.ts" };
const base = "@anthropic-ai/claude-agent-sdk";
const sdk = "/trusted/bridge/node_modules/sdk/sdk.mjs";
const missingConfig = () => { throw Object.assign(new Error("missing"), { code: "ENOENT" }); };

function resolver(config: unknown = {}, available: string[] = []) {
  const reads: string[] = [];
  const resolutions: [string, string][] = [];
  return {
    reads, resolutions,
    options: {
      readConfig: (path: string) => {
        reads.push(path);
        assert.equal(path, "/trusted/agent/claude-bridge.json", "never read a project config");
        return JSON.stringify(config);
      },
      exists: (path: string) => available.includes(path),
      resolveFrom: (anchor: string, specifier: string) => {
        resolutions.push([anchor, specifier]);
        assert.equal(anchor, specifier === base ? paths.bridgeEntry : sdk);
        if (specifier === base) return sdk;
        if (!available.includes(specifier)) throw new Error("not installed");
        return specifier;
      },
    },
  };
}

test("global CLI takes precedence, keeps path spaces, and never reads project config or PATH", () => {
  const cli = "/trusted/Claude Code/claude";
  const fixture = resolver({ provider: { pathToClaudeCodeExecutable: cli } }, [cli]);
  assert.equal(resolveClaudeLoginCli(paths, fixture.options), cli);
  assert.deepEqual(fixture.reads, ["/trusted/agent/claude-bridge.json"]);
  assert.deepEqual(fixture.resolutions, []);
});

test("invalid global config/paths fail closed instead of selecting a project or PATH CLI", () => {
  for (const configured of ["claude", "./project/claude", 42, "/missing/claude"]) {
    const fixture = resolver({ provider: { pathToClaudeCodeExecutable: configured } });
    assert.throws(() => resolveClaudeLoginCli(paths, fixture.options), /absolute|missing/);
    assert.deepEqual(fixture.resolutions, []);
  }
  for (const suffix of [".js", ".mjs", ".tsx", ".ts", ".jsx"]) {
    const fixture = resolver({ provider: { pathToClaudeCodeExecutable: `/trusted/cli${suffix}` } });
    assert.throws(() => resolveClaudeLoginCli(paths, fixture.options), /does not support configured JavaScript\/TypeScript/);
  }
  assert.throws(() => resolveClaudeLoginCli(paths, { readConfig: () => "SECRET malformed JSON" }), /Cannot read global/);
});

test("bundled CLI resolution is anchored to bridge then SDK, matching platform/libc precedence", () => {
  const cases = [
    { platform: "darwin", arch: "arm64", preferMusl: false, packages: [`${base}-darwin-arm64/claude`] },
    { platform: "win32", arch: "x64", preferMusl: false, packages: [`${base}-win32-x64/claude.exe`] },
    { platform: "android", arch: "arm64", preferMusl: false, packages: [`${base}-linux-arm64-android/claude`] },
    { platform: "linux", arch: "x64", preferMusl: false, packages: [`${base}-linux-x64/claude`, `${base}-linux-x64-musl/claude`] },
    { platform: "linux", arch: "arm64", preferMusl: true, packages: [`${base}-linux-arm64-musl/claude`, `${base}-linux-arm64/claude`] },
  ];
  for (const entry of cases) {
    for (const selected of entry.packages) {
      const fixture = resolver({}, [selected]);
      assert.equal(resolveClaudeLoginCli(paths, { ...fixture.options, ...entry, readConfig: missingConfig }), selected);
      assert.deepEqual(fixture.resolutions, [
        [paths.bridgeEntry, base],
        ...entry.packages.slice(0, entry.packages.indexOf(selected) + 1).map((pkg) => [sdk, pkg]),
      ]);
    }
    // When both Linux variants exist, choose the preferred libc first.
    const both = resolver({}, entry.packages);
    assert.equal(resolveClaudeLoginCli(paths, { ...both.options, ...entry }), entry.packages[0]);
  }
});

test("missing bundled executable/SDK report actionable errors with no PATH fallback", () => {
  const fixture = resolver();
  assert.throws(() => resolveClaudeLoginCli(paths, { ...fixture.options, platform: "darwin", arch: "arm64" }), /bundled CLI.*missing/);
  assert.throws(() => resolveClaudeLoginCli(paths, {
    ...fixture.options, resolveFrom: () => { throw new Error("missing SDK"); },
  }), /SDK is missing/);
  const absentFile = resolver({}, [`${base}-darwin-arm64/claude`]);
  assert.throws(() => resolveClaudeLoginCli(paths, {
    ...absentFile.options, exists: () => false, platform: "darwin", arch: "arm64",
  }), /bundled CLI.*missing/);
});

function commandHarness(options: { mode?: string; failAt?: string; status?: number | null; signal?: NodeJS.Signals; spawnError?: boolean; idle?: Promise<void> } = {}) {
  const events: string[] = [];
  const notifications: { message: string; level?: string }[] = [];
  const env = { ANTHROPIC_BASE_URL: "SECRET_URL", ANTHROPIC_API_KEY: "SECRET_KEY", ANTHROPIC_AUTH_TOKEN: "SECRET_TOKEN", CLAUDE_CONFIG_DIR: "/trusted/credentials" };
  let command: Parameters<ExtensionAPI["registerCommand"]>[1] | undefined;
  const event = (name: string) => {
    events.push(name);
    if (options.failAt === name) throw new Error("SECRET unexpected error");
  };
  const pi = {
    registerCommand: (name: string, definition: NonNullable<typeof command>) => {
      assert.equal(name, "claude-login");
      command = definition;
    },
  } as unknown as ExtensionAPI;
  registerClaudeBridgeLogin(pi, paths, {
    resolve: (receivedPaths) => { event("resolve"); assert.deepEqual(receivedPaths, paths); return "/trusted/Claude Code/claude"; },
    createCwd: () => { event("mkdir"); return "/trusted/empty-login"; },
    removeCwd: (cwd) => { assert.equal(cwd, "/trusted/empty-login"); event("remove"); },
    env,
    spawn: (cli, args, spawnOptions) => {
      event("spawn");
      assert.equal(cli, "/trusted/Claude Code/claude");
      assert.deepEqual(args, ["auth", "login"]);
      assert.deepEqual(spawnOptions, { cwd: "/trusted/empty-login", stdio: "inherit", env, shell: false });
      assert.strictEqual(spawnOptions.env, env);
      return { status: options.status === undefined ? 0 : options.status, signal: options.signal ?? null,
        ...(options.spawnError ? { error: new Error("SECRET subprocess error") } : {}) };
    },
  });
  assert.equal(events.length, 0, "factory registration must not start processes or perform IO");
  const tui = { stop: () => event("stop"), start: () => event("start"), requestRender: (force: boolean) => { assert.equal(force, true); event("render"); } };
  const ctx = {
    mode: options.mode ?? "tui", cwd: "/malicious/project", hasUI: true,
    waitForIdle: async () => { event("idle"); await options.idle; },
    ui: {
      notify: (message: string, level?: string) => notifications.push({ message, level }),
      custom: async (factory: (terminal: typeof tui, theme: never, kb: never, done: (value: unknown) => void) => unknown) => {
        event("custom");
        let result: unknown;
        const component = factory(tui, undefined as never, undefined as never, (value) => { event("done"); result = value; });
        assert.ok(component);
        return result;
      },
    },
  } as unknown as ExtensionCommandContext;
  return { events, notifications, env, run: (args = "") => command!.handler(args, ctx) };
}

test("login waits for idle, hands off TUI, directly spawns only auth login, then restores and cleans up", async () => {
  const fixture = commandHarness();
  await fixture.run();
  assert.deepEqual(fixture.events, ["idle", "resolve", "mkdir", "custom", "stop", "spawn", "start", "render", "done", "remove"]);
  assert.deepEqual(fixture.notifications.map((n) => n.level), ["warning", "info"]);
  const messages = fixture.notifications.map((n) => n.message).join("\n");
  for (const name of ["ANTHROPIC_BASE_URL", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]) assert.ok(messages.includes(name));
  assert.ok(!messages.includes("SECRET"));
  assert.equal(fixture.env.CLAUDE_CONFIG_DIR, "/trusted/credentials");
});

test("terminal handoff cannot begin until waitForIdle resolves", async () => {
  let release!: () => void;
  const fixture = commandHarness({ idle: new Promise<void>((resolve) => { release = resolve; }) });
  const pending = fixture.run();
  assert.deepEqual(fixture.events, ["idle"]);
  release();
  await pending;
  assert.equal(fixture.events.at(-1), "remove");
});

test("RPC/headless modes and extra arguments never wait, open custom UI, or spawn", async () => {
  for (const mode of ["rpc", "json", "print"]) {
    const fixture = commandHarness({ mode });
    await fixture.run();
    assert.deepEqual(fixture.events, []);
    assert.match(fixture.notifications[0].message, /requires Pi's interactive TUI/);
  }
  const fixture = commandHarness();
  await fixture.run("--console");
  assert.deepEqual(fixture.events, []);
  assert.match(fixture.notifications[0].message, /Usage/);
});

test("nonzero exits, cancellations, returned spawn errors and thrown launch errors restore TUI", async () => {
  for (const options of [{ status: 1 }, { status: null, signal: "SIGINT" as const }, { spawnError: true }, { failAt: "spawn" }]) {
    const fixture = commandHarness(options);
    await fixture.run();
    assert.deepEqual(fixture.events.slice(-4), ["start", "render", "done", "remove"]);
    assert.notEqual(fixture.notifications.at(-1)?.level, "info");
    assert.ok(!fixture.notifications.some((n) => n.message.includes("SECRET")));
  }
});

test("idle/resolution/custom and terminal errors still clean up and attempt terminal restoration", async () => {
  for (const failAt of ["idle", "resolve", "mkdir", "custom", "stop", "start", "render", "done"]) {
    const fixture = commandHarness({ failAt });
    await fixture.run();
    if (["idle", "resolve", "mkdir", "custom", "stop"].includes(failAt)) assert.ok(!fixture.events.includes("spawn"));
    if (["custom", "stop", "start", "render", "done"].includes(failAt)) assert.equal(fixture.events.at(-1), "remove");
    if (["stop", "start", "render", "done"].includes(failAt)) {
      assert.ok(fixture.events.includes("start"));
      assert.ok(fixture.events.includes("render"));
    }
    assert.equal(fixture.notifications.at(-1)?.level, "error");
    assert.ok(!fixture.notifications.some((n) => n.message.includes("SECRET")));
  }
});
