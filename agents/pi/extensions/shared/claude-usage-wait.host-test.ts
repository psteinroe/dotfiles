/** Offline bundled-Pi regression harness. See docs/pi.md; requires the pinned
 * bridge checkout via CLAUDE_BRIDGE_TEST_ENTRY and an isolated temporary HOME. */
import assert from "node:assert/strict";
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import * as path from "node:path";
import { pathToFileURL } from "node:url";
import { createAssistantMessageEventStream, createProvider, isRetryableAssistantError, type Api, type Model } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { activateClaudeBridgeFactory, guardClaudeBridgeProvider } from "../claude-bridge.ts";
import { prepareClaudeBridgeSource, patchClaudeBridgeSource } from "./claude-bridge-source.ts";
import { createClaudeUsageWait } from "./claude-usage-wait-extension.ts";
import { retryClaudeUsage } from "./claude-usage-wait.ts";

export default function hostTest(pi: ExtensionAPI) {
  const api = "openai-responses" as Api;
  const dummy = (model: any) => {
    const stream = createAssistantMessageEventStream();
    queueMicrotask(() => { stream.push({ type: "done", reason: "stop", message: message(model) }); stream.end(); });
    return stream;
  };
  pi.registerProvider(createProvider({ id: "usage-fixture", name: "fixture", auth: { apiKey: { name: "fixture", resolve: async () => ({ auth: { apiKey: "fixture" }, source: "fixture" }) } },
    models: [{ id: "fixture", name: "fixture", api, provider: "usage-fixture", baseUrl: "http://fixture.invalid", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 10000, maxTokens: 100 }],
    api: { stream: dummy, streamSimple: dummy } }));
  pi.on("session_start", async (_event, context) => {
    let source: ReturnType<typeof prepareClaudeBridgeSource> | undefined;
    const deadline = setTimeout(() => {
      process.stderr.write("CLAUDE_USAGE_WAIT_HOST_ERROR timed out\n");
      process.exit(1);
    }, 5000);
    try {
      assert.ok(path.basename(homedir()).startsWith("pi-claude-usage-host."), "Use a temporary HOME, never the real home.");
      process.env.CLAUDE_CONFIG_DIR = path.join(homedir(), ".claude");
      mkdirSync(path.join(homedir(), ".pi/agent"), { recursive: true });
      const entry = process.env.CLAUDE_BRIDGE_TEST_ENTRY;
      assert.ok(entry, "Set CLAUDE_BRIDGE_TEST_ENTRY to the pinned managed bridge src/index.ts");
      assert.throws(() => patchClaudeBridgeSource(readFileSync(entry, "utf8") + "\n"), /differs/);
      source = prepareClaudeBridgeSource(entry);
      // Test-only SDK seam. Never start Claude, access auth, or use a real model.
      const index = readFileSync(source.entryPath, "utf8");
      writeFileSync(source.entryPath, index.replace('import { query, type EffortLevel, type SDKMessage, type SettingSource } from "@anthropic-ai/claude-agent-sdk";', 'import { query } from "./fixture-query.ts";'));
      writeFileSync(path.join(path.dirname(source.entryPath), "fixture-query.ts"), 'export function query(request) { return globalThis[Symbol.for("claude-usage-fixture-query")](request); }\n');
      const bridge = await import(pathToFileURL(source.entryPath).href);
      const { QueryContext, ctx } = await import(pathToFileURL(path.join(path.dirname(source.entryPath), "query-state.js")).href);
      const model: Model<any> = { name: "fixture", baseUrl: "claude-bridge", reasoning: false, input: ["text"], api: "claude-bridge", provider: "claude-bridge", id: "claude-opus-5-5", contextWindow: 200000, maxTokens: 1000, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } };
      let now = Date.parse("2026-10-15T12:20:00Z");
      const rejected = { type: "rate_limit_event", rate_limit_info: { status: "rejected", rateLimitType: "five_hour", resetsAt: (now + 5 * 3600_000) / 1000 } };
      const result = { type: "result", subtype: "success", is_error: true, result: "You've hit your monthly spend limit · your session limit resets 5:20pm (UTC)" };
      const synthetic = { type: "assistant", error: "rate_limit", message: { model: "<synthetic>", content: [{ type: "text", text: result.result }] } };
      const success = { type: "result", subtype: "success", is_error: false, result: "healthy" };
      const consume = async (messages: any[], state = new QueryContext()) => {
        const events: any[] = [];
        state.resetTurnState(model);
        state.currentPiStream = { push: (e: any) => events.push(e), end() {} };
        await bridge.__test.consumeQuery((async function* () { yield* messages; })(), new Map(), model, () => false, state);
        return { state, events };
      };
      for (const status of ["allowed", "allowed_warning"]) {
        const warning = { ...rejected, rate_limit_info: { ...rejected.rate_limit_info, status } };
        const { state } = await consume([warning, success]);
        assert.equal(state.turnOutput.stopReason, "stop", "warnings must not stop healthy turns");
        assert.equal(state.turnOutput.claudeUsageLimit, undefined);
        const later = await consume([result], state);
        assert.equal(later.state.turnOutput.errorMessage, result.result, "stale warnings cannot relabel billing failures");
      }
      for (const messages of [
        [rejected, success, result],
        [rejected, { ...rejected, rate_limit_info: { ...rejected.rate_limit_info, status: "allowed_warning" } }, result],
        [rejected, { ...synthetic, error: "billing_error" }, result],
        [rejected, { ...synthetic, error: "authentication_failed" }, result],
      ]) {
        const { state } = await consume(messages);
        assert.equal(state.turnOutput.claudeUsageLimit, undefined);
        assert.equal(state.turnOutput.errorMessage, result.result);
      }
      const fresh = await consume([rejected, rejected, synthetic, result]);
      assert.deepEqual(fresh.state.turnOutput.claudeUsageLimit, rejected.rate_limit_info);
      assert.deepEqual(fresh.state.turnOutput.content, [], "synthetic failure text is not model output");
      assert.deepEqual((await consume([rejected, { ...synthetic, error: "unknown" }, result])).state.turnOutput.claudeUsageLimit, rejected.rate_limit_info, "unknown prose/error categories cannot override a fresh structured rejection");
      const updated = { ...rejected, rate_limit_info: { ...rejected.rate_limit_info, resetsAt: rejected.rate_limit_info.resetsAt + 60 } };
      assert.equal((await consume([rejected, updated, result])).state.turnOutput.claudeUsageLimit.resetsAt, updated.rate_limit_info.resetsAt);
      fresh.state.rateLimitRejection = rejected.rate_limit_info;
      fresh.state.resetTurnState(model);
      assert.equal(fresh.state.rateLimitRejection, null, "new tool/model turn clears stale rejection");

      const handlers = new Map<string, any[]>(), commands = new Map<string, any>();
      const entries: any[] = [], statuses: any[] = [];
      const fakeContext: any = { hasUI: true, mode: "tui", modelRegistry: { getProvider: () => undefined }, ui: { notify() {}, setStatus: (_key: string, value: any) => statuses.push(value) } };
      let registered: any;
      const fake: any = {
        on: (name: string, handler: any) => handlers.set(name, [...(handlers.get(name) ?? []), handler]),
        registerProvider: (_name: string, config: any) => { registered = config; },
        registerCommand: (name: string, command: any) => commands.set(name, command),
        appendEntry: (_name: string, data: any) => entries.push(data), events: { emit() {} },
      };
      const emit = async (name: string) => { for (const handler of handlers.get(name) ?? []) await handler({ reason: "new" }, fakeContext); };
      const wrap = createClaudeUsageWait(fake, { now: () => now, random: () => 0, sleep: async (ms, signal) => {
        signal.throwIfAborted();
        assert.deepEqual(await handlers.get("cache_warming_decision")![0](), { action: "stop" }, "waiting must not make cache-warming model calls");
        now += ms;
      } });
      activateClaudeBridgeFactory(guardClaudeBridgeProvider(fake, homedir(), wrap), bridge.default);
      await emit("session_start");
      assert.ok(registered);
      bridge.__test.promptCaptures.record("fixture", { contextFiles: [], skills: [] }, "fixture");
      const calls: any[] = [];
      let deliveries = 0, sideEffects = 0;
      (globalThis as any)[Symbol.for("claude-usage-fixture-query")] = (request: any) => {
        calls.push(request);
        const call = calls.length;
        return {
          async *[Symbol.asyncIterator]() {
            yield { type: "system", subtype: "init", session_id: `00000000-0000-4000-8000-${String(call).padStart(12, "0")}` };
            if (call === 1) {
              const delivered = new Promise<void>((resolve) => ctx().pendingToolCalls.set("effect-1", { toolName: "effect", resolve: () => { deliveries++; resolve(); } }));
              yield { type: "assistant", message: { content: [{ type: "tool_use", id: "effect-1", name: "mcp__custom-tools__effect", input: {} }] } };
              await delivered;
              yield rejected; yield rejected; yield synthetic; yield result;
            } else {
              assert.ok(request.options.resume, "retry must import completed Pi tool results");
              yield { type: "assistant", message: { content: [{ type: "text", text: "done" }] } };
              yield { ...success, result: "done" };
            }
          },
          close() {}, interrupt: async () => {},
        };
      };
      const transcript: any = { messages: [
        { role: "system", content: "fixture", timestamp: now, toolsAdded: [{ name: "effect", description: "fixture side effect", parameters: { type: "object", properties: {} } }] },
        { role: "user", content: "do it once", timestamp: now },
      ] };
      const first = await registered.streamSimple(model, transcript, {}).result();
      assert.equal(first.stopReason, "toolUse");
      sideEffects++;
      transcript.messages.push(first, { role: "toolResult", toolCallId: "effect-1", toolName: "effect", content: [{ type: "text", text: "already done" }], isError: false, timestamp: now });
      const final = await registered.streamSimple(model, transcript, {}).result();
      assert.equal(final.stopReason, "stop");
      assert.equal(final.content[0].text, "done");
      assert.equal(calls.length, 2, "duplicate rejection events must not create duplicate requests");
      assert.equal(deliveries, 1, "MCP results must not be released twice");
      assert.equal(sideEffects, 1);
      assert.equal(now, Date.parse("2026-10-15T17:20:05Z"));
      assert.equal(entries.filter((entry) => entry.phase === "waiting").length, 1);
      assert.ok(statuses.some((status) => status?.includes("Claude waiting")));
      assert.equal(statuses.at(-1), undefined);
      assert.equal(await handlers.get("cache_warming_decision")![0](), undefined, "normal warming policy resumes after wait");
      const history = readFileSync(bridge.__test.getSharedSession() ? findSessionFile(process.env.CLAUDE_CONFIG_DIR!, calls[1].options.resume) : "", "utf8");
      assert.ok(history.includes("already done"), "resumed history must contain completed tool result");

      const terminal: any[] = await collect(retryClaudeUsage(() => (async function* () {
        yield { type: "error", reason: "error", error: { ...message(model), stopReason: "error", claudeUsageLimit: rejected.rate_limit_info } } as any;
      })(), new AbortController().signal, { now: () => now, random: () => 0, sleep: async (ms) => { now += ms; } }));
      assert.equal(isRetryableAssistantError(terminal[0].error), false, "exhausted wait must not restart Pi's generic retry budget");

      // A cancellation and shutdown both end the pending request, never enqueue
      // a prompt. Reload creates a fresh adapter; saved entries are audit only.
      for (const action of ["cancel", "shutdown"]) {
        let attempts = 0;
        const cancelWrap = createClaudeUsageWait(fake, { now: () => now, random: () => 0, sleep: async (_ms, signal) => {
          if (action === "cancel") await commands.get("claude-wait-cancel").handler("", fakeContext);
          else await emit("session_shutdown");
          signal.throwIfAborted();
        } });
        await emit("session_start");
        const cancelled = await cancelWrap(() => {
          attempts++;
          const stream = createAssistantMessageEventStream();
          queueMicrotask(() => { stream.push({ type: "error", reason: "error", error: { ...message(model), stopReason: "error", claudeUsageLimit: rejected.rate_limit_info } } as any); stream.end(); });
          return stream;
        })(model, transcript, {}).result();
        assert.equal(cancelled.stopReason, "aborted"); assert.equal(attempts, 1);
      }
      assert.equal(sideEffects, 1);
      let parkedQueryAborted = false;
      const parkedWrap = createClaudeUsageWait(fake);
      await emit("session_start");
      await parkedWrap((_model, _transcript, options) => {
        options!.signal!.addEventListener("abort", () => { parkedQueryAborted = true; });
        const stream = createAssistantMessageEventStream();
        queueMicrotask(() => { stream.push({ type: "done", reason: "toolUse", message: { ...message(model), stopReason: "toolUse" } }); stream.end(); });
        return stream;
      })(model, transcript, {}).result();
      assert.equal(parkedQueryAborted, false);
      const savedEntries = entries.length;
      const savedCalls = calls.length;
      createClaudeUsageWait(fake, { sleep: async () => { throw new Error("reload must not restore a timer"); } });
      await emit("session_start");
      assert.equal(entries.length, savedEntries, "audit entries must not resurrect a cancelled or completed request");
      assert.equal(calls.length, savedCalls);
      await emit("session_shutdown");
      assert.equal(parkedQueryAborted, true, "shutdown must cancel the original SDK signal even after a tool stream completed");
      process.stderr.write("CLAUDE_USAGE_WAIT_HOST_OK structured-freshness tool-result-resume no-replay cancellation shutdown retry-budget\n");
    } catch (error) {
      process.stderr.write(`CLAUDE_USAGE_WAIT_HOST_ERROR ${error instanceof Error ? error.stack : String(error)}\n`);
      process.exitCode = 1;
    } finally {
      clearTimeout(deadline);
      source?.dispose();
      delete (globalThis as any)[Symbol.for("claude-usage-fixture-query")];
      context.shutdown();
    }
  });
}

async function collect<T>(values: AsyncIterable<T>): Promise<T[]> {
  const result: T[] = [];
  for await (const value of values) result.push(value);
  return result;
}
function message(model: any): any {
  return { role: "assistant", api: model.api, provider: model.provider, model: model.id, content: [], stopReason: "stop", timestamp: Date.now(), usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } };
}
function findSessionFile(root: string, id: string): string {
  for (const entry of readdirSync(root, { withFileTypes: true, recursive: true })) {
    if (entry.name === `${id}.jsonl`) return path.join(entry.parentPath, entry.name);
  }
  throw new Error(`No fixture CC session ${id}`);
}
