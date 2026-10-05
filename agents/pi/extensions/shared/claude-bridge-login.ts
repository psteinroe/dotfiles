import { spawnSync, type SpawnSyncOptions } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

interface LoginPaths {
  agentDir: string;
  bridgeEntry: string;
}

interface ResolverOptions {
  platform?: string;
  arch?: string;
  preferMusl?: boolean;
  readConfig?: (path: string) => string;
  exists?: (path: string) => boolean;
  resolveFrom?: (anchor: string, specifier: string) => string;
}

class LoginError extends Error {}

export function resolveClaudeLoginCli(paths: LoginPaths, options: ResolverOptions = {}): string {
  const exists = options.exists ?? existsSync;
  const readConfig = options.readConfig ?? ((path) => readFileSync(path, "utf8"));
  let config: { provider?: { pathToClaudeCodeExecutable?: unknown } };
  try {
    config = JSON.parse(readConfig(join(paths.agentDir, "claude-bridge.json")));
    if (!config || typeof config !== "object") throw new Error("Invalid config");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") config = {};
    else throw new LoginError("Cannot read global claude-bridge.json. Fix it before using /claude-login.");
  }

  const configured = config.provider?.pathToClaudeCodeExecutable;
  if (configured !== undefined && configured !== "") {
    // Never interpret a relative path as a project path or a PATH command.
    if (typeof configured !== "string" || !isAbsolute(configured)) {
      throw new LoginError("Global provider.pathToClaudeCodeExecutable must be an absolute CLI path.");
    }
    // SDK 0.3.280 runs these suffixes through node/bun, not as native binaries.
    // Pi can itself be a compiled Bun executable, so process.execPath is not a
    // reliable JS runtime. Reject rather than silently launch Pi or PATH claude.
    if ([".js", ".mjs", ".tsx", ".ts", ".jsx"].some((suffix) => configured.endsWith(suffix))) {
      throw new LoginError("/claude-login does not support configured JavaScript/TypeScript CLIs. Configure an absolute native Claude Code CLI path.");
    }
    if (!exists(configured)) throw new LoginError("Configured Claude Code CLI is missing. Fix global provider.pathToClaudeCodeExecutable.");
    return configured;
  }

  const platform = options.platform ?? process.platform;
  const arch = options.arch ?? process.arch;
  // Match SDK 0.3.280's getReport/glibc detection and optional-package order.
  const report = platform === "linux" && typeof process.report?.getReport === "function"
    ? process.report.getReport() as { header?: { glibcVersionRuntime?: string } } : null;
  const preferMusl = options.preferMusl ?? (report !== null && report.header?.glibcVersionRuntime === undefined);
  const base = "@anthropic-ai/claude-agent-sdk";
  const packages = platform === "android" ? [`${base}-linux-${arch}-android`]
    : platform === "linux" ? (preferMusl ? [`${base}-linux-${arch}-musl`, `${base}-linux-${arch}`]
      : [`${base}-linux-${arch}`, `${base}-linux-${arch}-musl`])
    : [`${base}-${platform}-${arch}`];
  const resolveFrom = options.resolveFrom ?? ((anchor, specifier) => createRequire(anchor).resolve(specifier));
  let sdk: string;
  try {
    sdk = resolveFrom(paths.bridgeEntry, base);
  } catch {
    throw new LoginError("Bridge Claude Agent SDK is missing. Reinstall pi-claude-bridge with optional dependencies.");
  }
  for (const pkg of packages) {
    try {
      const cli = resolveFrom(sdk, `${pkg}/claude${platform === "win32" ? ".exe" : ""}`);
      if (exists(cli)) return cli;
    } catch { /* Try the SDK's next platform candidate. */ }
  }
  throw new LoginError(`Bridge bundled CLI for ${platform}-${arch} is missing. Reinstall pi-claude-bridge with optional dependencies or configure a global native CLI path.`);
}

type LoginResult = { status: number | null; signal: NodeJS.Signals | null; error?: Error };
interface LoginDependencies {
  resolve: (paths: LoginPaths) => string;
  createCwd: () => string;
  removeCwd: (cwd: string) => void;
  spawn: (cli: string, args: string[], options: SpawnSyncOptions) => LoginResult;
  env: NodeJS.ProcessEnv;
}

export function registerClaudeBridgeLogin(
  pi: ExtensionAPI,
  paths: LoginPaths,
  overrides: Partial<LoginDependencies> = {},
): void {
  // Registration performs no IO or process startup.
  const deps: LoginDependencies = {
    resolve: resolveClaudeLoginCli,
    createCwd: () => mkdtempSync(join(tmpdir(), "pi-claude-login-")),
    removeCwd: (cwd) => rmSync(cwd, { recursive: true, force: true }),
    spawn: spawnSync,
    env: process.env,
    ...overrides,
  };
  pi.registerCommand("claude-login", {
    description: "Sign in using Claude Bridge's Claude Code CLI (TUI only)",
    handler: async (args, ctx) => {
      if (ctx.mode !== "tui") {
        ctx.ui.notify("/claude-login requires Pi's interactive TUI (not RPC or headless mode).", "error");
        return;
      }
      if (args.trim()) {
        ctx.ui.notify("Usage: /claude-login (no arguments)", "error");
        return;
      }
      try {
        await ctx.waitForIdle();
        const cli = deps.resolve(paths);
        const names = ["ANTHROPIC_BASE_URL", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]
          .filter((name) => deps.env[name] !== undefined);
        if (names.length) ctx.ui.notify(`Environment overrides may affect Claude Code authentication: ${names.join(", ")}`, "warning");
        // Claude Code owns credential storage; inherit CLAUDE_CONFIG_DIR and
        // all other env unchanged. Only cwd is isolated from project config.
        const cwd = deps.createCwd();
        try {
          const result = await ctx.ui.custom<LoginResult>((tui, _theme, _kb, done) => {
            let result: LoginResult;
            try {
              tui.stop();
              result = deps.spawn(cli, ["auth", "login"], { cwd, stdio: "inherit", env: deps.env, shell: false });
            } catch {
              result = { status: null, signal: null, error: new Error("Launch failed") };
            } finally {
              try { tui.start(); } finally { tui.requestRender(true); }
            }
            done(result);
            return { render: () => [], invalidate: () => {} };
          });
          if (result.error) throw new LoginError("Unable to launch Claude Code auth login. Check the native CLI and its execute permissions.");
          if (result.signal) ctx.ui.notify("Claude Code login cancelled or interrupted.", "warning");
          else if (result.status === 0) ctx.ui.notify("Claude Code login completed. Credentials remain managed by Claude Code, not Pi.", "info");
          else ctx.ui.notify(`Claude Code login did not complete (exit ${result.status ?? "unknown"}).`, "error");
        } finally {
          deps.removeCwd(cwd);
        }
      } catch (error) {
        // Do not echo arbitrary process/config errors that might contain secrets.
        ctx.ui.notify(error instanceof LoginError ? error.message : "Claude Code login failed. Pi's terminal handoff could not complete.", "error");
      }
    },
  });
}
