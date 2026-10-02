import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { claudeKeychainService, codexAccountId, readClaudeCredential, readUsageCredential, type ClaudeCredentialSources } from "./credential-source.ts";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

const signal = () => new AbortController().signal;
const stored = (access = "fixture-secret") => JSON.stringify({ claudeAiOauth: { accessToken: access, refreshToken: "NEVER_RETURN", expiresAt: Date.now() + 3600000 } });
function sources(overrides: Partial<ClaudeCredentialSources> = {}): ClaudeCredentialSources {
  return { env: {}, platform: "linux", home: "/fixture", username: "fixture", read: async () => stored(),
    keychain: async () => { throw new Error("absent"); }, ...overrides };
}
test("Claude Linux reads only the configured credential file and never returns refresh tokens", async () => {
  const value = await readClaudeCredential(signal(), sources({ env: { CLAUDE_CONFIG_DIR: "/custom" }, read: async (file) => {
    assert.equal(file, "/custom/.credentials.json"); return stored();
  } }));
  assert.deepEqual(value, { access: "fixture-secret" });
});
test("Claude environment token avoids all store reads; invalid env does not fall back", async () => {
  const unavailable = async () => { throw new Error("must not read"); };
  assert.deepEqual(await readClaudeCredential(signal(), sources({ env: { CLAUDE_CODE_OAUTH_TOKEN: "fixture-env" }, read: unavailable })), { access: "fixture-env" });
  assert.equal(await readClaudeCredential(signal(), sources({ env: { CLAUDE_CODE_OAUTH_TOKEN: "injected\nheader" }, read: unavailable })), undefined);
  assert.equal(await readClaudeCredential(signal(), sources({ env: { ANTHROPIC_API_KEY: "fixture-api-key" }, read: unavailable })), undefined);
});
test("Claude macOS follows keychain service/account naming and authoritative expiration", async () => {
  assert.equal(claudeKeychainService({}, "/fixture"), "Claude Code-credentials");
  const hash = createHash("sha256").update("/custom").digest("hex").slice(0, 8);
  assert.equal(claudeKeychainService({ CLAUDE_CONFIG_DIR: "/custom" }, "/fixture"), `Claude Code-credentials-${hash}`);
  assert.equal(claudeKeychainService({ CLAUDE_CONFIG_DIR: "/custom", CLAUDE_SECURESTORAGE_CONFIG_DIR: "" }, "/fixture"), "Claude Code-credentials");
  const value = await readClaudeCredential(signal(), sources({ platform: "darwin", keychain: async (service, account) => {
    assert.equal(service, "Claude Code-credentials"); assert.equal(account, "fixture"); return stored("fixture-keychain");
  }, read: async () => { throw new Error("must not fall back"); } }));
  assert.deepEqual(value, { access: "fixture-keychain" });
  assert.equal(await readClaudeCredential(signal(), sources({ platform: "darwin", keychain: async () => JSON.stringify({ claudeAiOauth: { accessToken: "expired", expiresAt: 1 } }),
    read: async () => { throw new Error("must not fall back to another account"); } })), undefined);
});
test("missing keychain falls back to file; malformed or missing credentials remain unknown", async () => {
  assert.deepEqual(await readClaudeCredential(signal(), sources({ platform: "darwin" })), { access: "fixture-secret" });
  assert.equal(await readClaudeCredential(signal(), sources({ read: async () => "not JSON" })), undefined);
  assert.equal(await readClaudeCredential(signal(), sources({ read: async () => { throw new Error("fixture-secret"); } })), undefined);
});
test("Codex uses Pi's public provider auth resolver, not files or account aliases", async () => {
  const token = `e30.${Buffer.from(JSON.stringify({ "https://api.openai.com/auth": { chatgpt_account_id: "fixture-account" } })).toString("base64url")}.fixture`;
  const ctx = { modelRegistry: { getProviderAuth: async (provider: string) => {
    assert.equal(provider, "openai-codex"); return { auth: { apiKey: token } };
  } } } as unknown as ExtensionContext;
  assert.deepEqual(await readUsageCredential("openai-codex", ctx, signal()), { access: token, accountId: "fixture-account" });
  assert.equal(codexAccountId("proxy-placeholder"), undefined);
  assert.equal(codexAccountId("sk-fixture"), undefined);
});
test("cancelled readers do not access stores", async () => {
  const controller = new AbortController(); controller.abort();
  let calls = 0;
  await assert.rejects(readClaudeCredential(controller.signal, sources({ read: async () => { calls++; return stored(); } })));
  assert.equal(calls, 0);
});
