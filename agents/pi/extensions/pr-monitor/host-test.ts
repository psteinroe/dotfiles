/** Bundled-Pi adapter smoke test; use a fresh temporary HOME and PI_CODING_AGENT_DIR.
 * pi --no-extensions --no-tools --no-session --offline -e <this-file> \
 *   --model openai-codex/pr-monitor-fixture -p smoke
 * Success prints PR_MONITOR_HOST_OK. No GitHub/model network requests are made.
 */
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { createAssistantMessageEventStream, createProvider, type Api } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import install from "./index.ts";

async function until(check: () => boolean | Promise<boolean>): Promise<void> {
  const deadline = Date.now() + 5000;
  while (!(await check())) {
    if (Date.now() > deadline) throw new Error("Host assertion timed out.");
    await new Promise(resolve => setTimeout(resolve, 20));
  }
}

export default function hostTest(pi: ExtensionAPI) {
  const api = "openai-responses" as Api;
  const stream = (model: any) => {
    const result = createAssistantMessageEventStream();
    const message: any = { role: "assistant", content: [{ type: "text", text: "fixture" }], api, provider: model.provider, model: model.id,
      usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } }, stopReason: "stop", timestamp: Date.now() };
    queueMicrotask(() => { result.push({ type: "done", reason: "stop", message }); result.end(message); });
    return result;
  };
  pi.registerProvider(createProvider({ id: "openai-codex", name: "PR monitor fixture", auth: { apiKey: { name: "fixture", resolve: async () => ({ auth: { apiKey: "fixture" }, source: "fixture" }) } },
    models: [{ id: "pr-monitor-fixture", name: "fixture", api, provider: "openai-codex", baseUrl: "http://fixture.invalid", reasoning: false, input: ["text"], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 10000, maxTokens: 100 }],
    api: { stream, streamSimple: stream } }));
  pi.on("session_start", async (_event, context) => {
    const root = os.homedir();
    assert.ok(path.basename(root).startsWith("pi-pr-monitor-host."), "use a fresh /tmp/pi-pr-monitor-host.XXXXXX HOME, never the real home");
    process.env.HERDR_ENV = "0"; // fixture reporting must not touch the caller's real pane
    const tools = new Map<string, any>(), handlers = new Map<string, any[]>();
    const messages: any[] = [];
    let idle = false;
    const fakeContext: any = { cwd: root, mode: "tui", hasUI: true, isIdle: () => idle, hasPendingMessages: () => false, ui: { setStatus() {} } };
    const fake: any = { registerTool(tool: any) { tools.set(tool.name, tool); }, registerCommand() {},
      on(event: string, handler: any) { handlers.set(event, [...(handlers.get(event) ?? []), handler]); },
      async sendMessage(message: any, options: any) { messages.push({ message, options }); } };
    const emit = async (name: string, event: any = {}) => { for (const handler of handlers.get(name) ?? []) await handler(event, fakeContext); };
    try {
      const bin = path.join(root, "bin"); fs.mkdirSync(bin);
      const payload = { url: "https://github.com/example/project/pull/123", headRefOid: "a".repeat(40), state: "OPEN", isDraft: false, labels: [], mergeable: "MERGEABLE", mergeStateStatus: "CLEAN", statusCheckRollup: [{ name: "Test", status: "COMPLETED", conclusion: "FAILURE" }] };
      fs.writeFileSync(path.join(bin, "gh"), `#!/bin/sh\nprintf '%s\\n' "$*" >> ${JSON.stringify(path.join(root, "gh.log"))}\nprintf '%s\\n' '${JSON.stringify(payload)}'\n`, { mode: 0o700 });
      process.env.PATH = `${bin}${path.delimiter}${process.env.PATH}`;
      install(fake);
      assert.deepEqual([...tools.keys()].sort(), ["pr_watch_cancel", "pr_watch_status", "watch_pr"]);
      await emit("session_start");
      const call = (name: string, args: any) => tools.get(name).execute("host", args, undefined, undefined, fakeContext);
      const watch = await call("watch_pr", { pr: payload.url });
      assert.equal(watch.details.id, "pr-watch-1");
      await until(async () => (await call("pr_watch_status", { id: watch.details.id })).details.status === "failed");
      assert.equal(messages.length, 0, "busy coordinator must not be interrupted");
      await emit("session_shutdown", { reason: "reload" });
      handlers.clear(); tools.clear(); install(fake); await emit("session_start");
      assert.equal((await call("pr_watch_status", { id: watch.details.id })).details.status, "failed", "reload lost the subscription");
      idle = true; await emit("agent_settled"); await until(() => messages.length === 1);
      assert.equal(messages[0].options.deliverAs, "followUp");
      assert.equal(messages[0].options.triggerTurn, true);
      assert.match(messages[0].message.content, /not merge authorization/);
      assert.match(messages[0].message.content, /state_file/);
      const ready = await call("watch_pr", { pr: payload.url, until: "ready" });
      await call("pr_watch_cancel", { id: ready.details.id });
      assert.equal((await call("pr_watch_status", { id: ready.details.id })).details.status, "cancelled");
      assert.doesNotMatch(fs.readFileSync(path.join(root, "gh.log"), "utf8"), /^pr (merge|review|edit|comment|close)\b/m);
      await emit("session_shutdown", { reason: "exit" });
      console.log("PR_MONITOR_HOST_OK tools reload idle-delivery cancellation read-only");
    } catch (error) {
      await emit("session_shutdown", { reason: "exit" });
      console.error(`PR_MONITOR_HOST_ERROR ${error instanceof Error ? error.stack : String(error)}`);
      process.exitCode = 1;
    } finally { context.shutdown(); }
  });
}
