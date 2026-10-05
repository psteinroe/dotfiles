import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import * as os from "node:os";
import * as path from "node:path";
import { PrMonitor, watchSummary, type WatchSnapshot } from "./manager.ts";
import { SharedStore } from "./store.ts";
import { HerdrBackgroundMetadata } from "../background-terminals/src/herdr-metadata.ts";

const KEY = Symbol.for("dotfiles.pi.pr-monitor.v1");
interface Runtime { bind(pi: ExtensionAPI): void }
const slot = globalThis as typeof globalThis & { [KEY]?: Runtime };

export default function prMonitorExtension(initialPi: ExtensionAPI) {
  if (slot[KEY]) { slot[KEY].bind(initialPi); return; }
  let pi = initialPi;
  let ctx: ExtensionContext | undefined;
  let monitor: PrMonitor | undefined;
  let deliveryTimer: ReturnType<typeof setTimeout> | undefined;
  let delivering = false;
  const metadata = new HerdrBackgroundMetadata("pi:pr-monitor");
  const pending = new Map<string, WatchSnapshot>();
  const registrations: ((api: ExtensionAPI) => void)[] = [];
  const runtime: Runtime = { bind(api) { pi = api; for (const register of registrations) register(api); } };
  const register = (action: (api: ExtensionAPI) => void) => { registrations.push(action); action(pi); };
  const active = () => monitor?.list().filter(w => w.status === "watching") ?? [];
  const refresh = () => {
    if (ctx?.mode === "tui") void metadata.setActive(active().length > 0);
    if (ctx?.hasUI) ctx.ui.setStatus("pr-monitor", active().length ? `${active().length} PR watch${active().length === 1 ? "" : "es"} · /pr-watches` : undefined);
  };
  const scheduleDelivery = () => {
    if (!pending.size || deliveryTimer) return;
    deliveryTimer = setTimeout(() => { deliveryTimer = undefined; void flush(); }, 1_000);
    deliveryTimer.unref?.();
  };
  const flush = async () => {
    if (delivering || !pending.size) return;
    if (!ctx?.isIdle() || ctx.hasPendingMessages()) { scheduleDelivery(); return; }
    delivering = true;
    const batch = [...pending.values()].slice(0, 4);
    try {
      await pi.sendMessage({ customType: "pr-watch-result", content: [
        "PR monitor update (read-only; not merge authorization). Revalidate the head, checks, ready label and applicable user authorization before any merge.",
        ...batch.map(watch => JSON.stringify({ ...watchSummary(watch), state_file: path.join(monitor!.store.directory, `${watch.target.key}.json`) })),
      ].join("\n"), display: true, details: { watches: batch.map(watchSummary) } }, { deliverAs: "followUp", triggerTurn: true });
      for (const watch of batch) if (pending.get(watch.id) === watch) pending.delete(watch.id);
    } catch { /* Reload or queued messages can defer delivery; retain results. */ }
    finally { delivering = false; scheduleDelivery(); }
  };
  const getMonitor = () => {
    if (!ctx) throw new Error("PR monitor requires a started Pi session.");
    if (!monitor) {
      monitor = new PrMonitor(new SharedStore(path.join(os.homedir(), ".cache", "pi", "pr-monitor")), {
        notify(watch) { pending.set(watch.id, watch); refresh(); scheduleDelivery(); },
      });
      monitor.start();
    }
    return monitor;
  };
  const result = (details: unknown) => {
    const text = JSON.stringify(details);
    return { content: [{ type: "text" as const, text: text.length <= 32_000 ? text : `${text.slice(0, 32_000)}\n[Output truncated; inspect an individual subscription with pr_watch_status.]` }], details };
  };

  register(api => api.on("session_start", async (_event, context) => { ctx = context; refresh(); scheduleDelivery(); }));
  register(api => api.on("agent_settled", async (_event, context) => { ctx = context; scheduleDelivery(); }));
  register(api => api.on("session_shutdown", async event => {
    ctx?.ui.setStatus("pr-monitor", undefined);
    ctx = undefined;
    if (event.reason === "reload") return;
    monitor?.shutdown();
    monitor = undefined;
    await metadata.shutdown();
    pending.clear();
    if (deliveryTimer) clearTimeout(deliveryTimer);
    deliveryTimer = undefined;
    if (slot[KEY] === runtime) delete slot[KEY];
  }));
  register(api => api.registerTool({
    name: "watch_pr", label: "Watch Pull Request",
    description: "Monitor a GitHub PR asynchronously. Shares one poller per host/repository/PR/head SHA across Pi processes on this machine. Wait for stable automated checks, or checks plus the ready label. Reports failures, conflicts, new heads, draft/closed/merged state, errors and timeout. Read-only: never merges or changes review state. Returns a subscription ID; meaningful updates resume the agent automatically.",
    promptSnippet: "Start a shared PR checks/ready watcher without polling",
    promptGuidelines: [
      "Use watch_pr for pending PR checks or waiting for the ready label instead of shell watch loops. Repeated calls for the same head and goal reuse the session's subscription.",
      "After watch_pr returns, continue independent work or end the turn. Completion resumes the agent automatically; use pr_watch_status only to unblock immediate work, not for polling.",
      "A head_changed result ends the old-head watch. Inspect the new head and start a new watch if needed. A passed/ready result is observed state, never merge authorization.",
    ],
    parameters: Type.Object({
      pr: Type.String({ description: "PR number in the current working directory's repository, or an HTTPS PR URL." }),
      repo: Type.Optional(Type.String({ description: "Explicit owner/repo when pr is a number outside the current repository." })),
      until: Type.Optional(Type.Union([Type.Literal("checks"), Type.Literal("ready")], { description: "checks (default): stable checks; ready: stable checks AND the ready label." })),
      timeout_seconds: Type.Optional(Type.Integer({ minimum: 1, maximum: 604800, description: "Default 3600 for checks; 86400 for ready." })),
    }, { additionalProperties: false }),
    async execute(_id, params, signal, _onUpdate, context) {
      ctx = context;
      const manager = getMonitor();
      const target = await manager.resolve(params.pr, params.repo, context.cwd, signal);
      if (signal?.aborted) throw new Error("PR watch cancelled before acceptance.");
      const goal = params.until ?? "checks";
      const watch = manager.watch(target, goal, context.cwd, params.timeout_seconds ?? (goal === "ready" ? 86400 : 3600));
      refresh();
      void manager.tick().catch(() => undefined);
      return result({ ...watchSummary(watch), message: "Subscribed. Continue independent work or end the turn; meaningful updates arrive automatically. No merge authorization is implied." });
    },
  }));
  register(api => api.registerTool({
    name: "pr_watch_status", label: "PR Watch Status", description: "Inspect one session PR subscription or list all. Use only when needed to unblock immediate work, not for polling.",
    parameters: Type.Object({ id: Type.Optional(Type.String()) }, { additionalProperties: false }),
    async execute(_id, params) {
      if (!monitor) { if (params.id) throw new Error(`Unknown PR subscription ${params.id}.`); return result([]); }
      return result(params.id ? watchSummary(monitor.get(params.id)) : monitor.list().map(watchSummary));
    },
  }));
  register(api => api.registerTool({
    name: "pr_watch_cancel", label: "Cancel PR Watch", description: "Cancel only this session's PR subscription. Other sessions watching the same PR are unaffected. Does not change the PR.",
    parameters: Type.Object({ id: Type.String() }, { additionalProperties: false }),
    async execute(_id, params) {
      if (!monitor) throw new Error(`Unknown PR subscription ${params.id}.`);
      const watch = monitor.cancel(params.id);
      pending.delete(params.id);
      refresh();
      return result(watchSummary(watch));
    },
  }));
  register(api => api.registerCommand("pr-watches", {
    description: "List PR subscriptions; /pr-watches cancel <id> cancels yours",
    async handler(args, context) {
      const words = args.trim().split(/\s+/);
      if (words[0] === "cancel" && words[1]) {
        if (!monitor) throw new Error(`Unknown PR subscription ${words[1]}.`);
        monitor.cancel(words[1]); pending.delete(words[1]); refresh();
      }
      context.ui.notify(JSON.stringify(monitor?.list().map(watchSummary) ?? []), "info");
    },
  }));
  slot[KEY] = runtime;
}
