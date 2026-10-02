import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { homedir, userInfo } from "node:os";
import path from "node:path";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { bearer, type UsageCredential, type UsageProvider } from "./core.ts";

export interface ClaudeCredentialSources {
  env: NodeJS.ProcessEnv;
  platform: NodeJS.Platform;
  home: string;
  username: string;
  read(path: string, signal: AbortSignal): Promise<string>;
  keychain(service: string, account: string, signal: AbortSignal): Promise<string>;
}

export function claudeKeychainService(env: NodeJS.ProcessEnv, home: string): string {
  const override = env.CLAUDE_SECURESTORAGE_CONFIG_DIR;
  const custom = override !== undefined ? !!override : !!env.CLAUDE_CONFIG_DIR;
  const dir = (override ?? env.CLAUDE_CONFIG_DIR ?? path.join(home, ".claude")).normalize("NFC");
  return `Claude Code-credentials${custom ? `-${createHash("sha256").update(dir).digest("hex").slice(0, 8)}` : ""}`;
}

function parseClaudeCredential(text: string): UsageCredential | undefined {
  try {
    const value = JSON.parse(text)?.claudeAiOauth;
    // Claude Code owns refresh; this extension never copies or updates its store.
    if (typeof value?.expiresAt === "number" && value.expiresAt <= Date.now()) return undefined;
    return bearer(value?.accessToken) ? { access: value.accessToken } : undefined;
  } catch { return undefined; }
}

export async function readClaudeCredential(signal: AbortSignal, sources: ClaudeCredentialSources): Promise<UsageCredential | undefined> {
  signal.throwIfAborted();
  const { env } = sources;
  if (env.CLAUDE_CODE_OAUTH_TOKEN) return bearer(env.CLAUDE_CODE_OAUTH_TOKEN) ? { access: env.CLAUDE_CODE_OAUTH_TOKEN } : undefined;
  // These routes do not use the Claude subscription represented by this endpoint.
  if (env.ANTHROPIC_API_KEY || env.ANTHROPIC_AUTH_TOKEN || env.ANTHROPIC_BASE_URL ||
      [env.CLAUDE_CODE_USE_BEDROCK, env.CLAUDE_CODE_USE_VERTEX, env.CLAUDE_CODE_USE_FOUNDRY].some((value) => value === "1" || value === "true")) return undefined;
  signal.throwIfAborted();
  if (sources.platform === "darwin") {
    try {
      const account = /^[A-Za-z0-9._-]+$/.test(sources.username) ? sources.username : "claude-code-user";
      const text = await sources.keychain(claudeKeychainService(env, sources.home), account, signal);
      signal.throwIfAborted();
      if (text.trim()) return parseClaudeCredential(text);
    } catch { signal.throwIfAborted(); }
  }
  try {
    const dir = (env.CLAUDE_CONFIG_DIR ?? path.join(sources.home, ".claude")).normalize("NFC");
    const credential = parseClaudeCredential(await sources.read(path.join(dir, ".credentials.json"), signal));
    signal.throwIfAborted();
    return credential;
  } catch { signal.throwIfAborted(); return undefined; }
}

export function codexAccountId(access: string): string | undefined {
  try {
    const payload = JSON.parse(Buffer.from(access.split(".")[1], "base64url").toString("utf8"));
    const id = payload?.["https://api.openai.com/auth"]?.chatgpt_account_id;
    return typeof id === "string" && /^[A-Za-z0-9_-]{1,256}$/.test(id) ? id : undefined;
  } catch { return undefined; }
}

export async function readUsageCredential(provider: UsageProvider, ctx: ExtensionContext, signal: AbortSignal): Promise<UsageCredential | undefined> {
  signal.throwIfAborted();
  if (provider === "openai-codex") {
    // Host-bound public API; Pi owns its normal OAuth refresh, not this extension.
    const resolved = await ctx.modelRegistry.getProviderAuth("openai-codex");
    signal.throwIfAborted();
    const access = resolved?.auth.apiKey;
    if (!bearer(access)) return undefined;
    const accountId = codexAccountId(access);
    // No API keys or legacy loopback/proxy placeholders go to the quota endpoint.
    return accountId ? { access, accountId } : undefined;
  }
  return readClaudeCredential(signal, {
    env: process.env, platform: process.platform, home: homedir(),
    username: process.env.USER || userInfo().username,
    read: (file, signal) => readFile(file, { encoding: "utf8", signal }),
    keychain: (service, account, signal) => new Promise((resolve, reject) => {
      execFile("/usr/bin/security", ["find-generic-password", "-a", account, "-w", "-s", service],
        { encoding: "utf8", timeout: 5000, maxBuffer: 64 * 1024, signal },
        (error, stdout) => error ? reject(new Error("Keychain unavailable")) : resolve(stdout));
    }),
  });
}
