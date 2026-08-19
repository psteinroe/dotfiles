/**
 * Background terminals — long-running shell commands that keep running while
 * the agent works.
 *
 * Tools: bg_start / bg_status / bg_list / bg_kill
 * Command: /ps (list, and `/ps kill <id>`)
 *
 * When a terminal exits, its result is delivered as a follow-up message so the
 * agent learns the outcome without polling — unless bg_status or bg_kill
 * already showed it, in which case the automatic delivery is suppressed to
 * avoid telling the model the same thing twice.
 *
 * Process management lives in src/manager.ts.
 *
 * Vendored from @parke.dev/pi-background-terminals@0.1.0 (MIT).
 * See README.md and LICENSE in this directory.
 */

import * as path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
	formatBytes,
	formatElapsed,
	MAX_RUNNING,
	tail,
	TerminalManager,
	type TerminalSnapshot,
} from "./src/manager.ts";
import { BackgroundTerminalDelivery } from "./src/delivery.ts";
import { HerdrBackgroundMetadata } from "./src/herdr-metadata.ts";

/** Model-facing output caps. Status is generous; completion is compact. */
const STATUS_STDOUT_MAX = 16 * 1024;
const STATUS_STDERR_MAX = 8 * 1024;
const STATUS_STDOUT_LINES = 400;
const STATUS_STDERR_LINES = 200;
const RESULT_STDOUT_MAX = 8 * 1024;
const RESULT_STDERR_MAX = 4 * 1024;
const RESULT_STDOUT_LINES = 40;
const RESULT_STDERR_LINES = 20;

const RESULT_MESSAGE_TYPE = "background-terminal-result";
const UI_KEY = "background-terminals";
const RUNTIME_VERSION = "2026-08-19.4";

const glyph = (status: TerminalSnapshot["status"]): string =>
	status === "running" ? "●" : status === "done" ? "✓" : status === "killed" ? "⊘" : "✗";

export function backgroundTerminalStatus(running: number) {
	return running > 0 ? `● ${running} background terminal${running === 1 ? "" : "s"} · /ps` : undefined;
}

function describe(snapshot: TerminalSnapshot): string {
	const age = formatElapsed(snapshot.createdAt, snapshot.settledAt);
	const exit =
		snapshot.status === "running"
			? ""
			: snapshot.signal
				? ` signal=${snapshot.signal}`
				: snapshot.exitCode !== undefined && snapshot.exitCode !== null
					? ` exit=${snapshot.exitCode}`
					: "";
	return `${glyph(snapshot.status)} ${snapshot.id} [${snapshot.status}${exit}] "${snapshot.title}" ${age} out=${formatBytes(
		snapshot.stdout.totalBytes,
	)} err=${formatBytes(snapshot.stderr.totalBytes)}`;
}

function section(
	label: string,
	view: TerminalSnapshot["stdout"],
	maxBytes: number,
	maxLines: number,
	omitEmpty = false,
): string | undefined {
	if (!view.text) return omitEmpty ? undefined : `${label}: (empty)`;
	const result = tail(view.text, maxBytes, maxLines);
	const note =
		result.truncated || view.truncatedBytes > 0
			? ` [truncated: showing the last ${formatBytes(Buffer.byteLength(result.text, "utf8"))} of ${formatBytes(
					view.totalBytes,
				)}]`
			: "";
	return `${label}${note}:\n${result.text}`;
}

function statusText(snapshot: TerminalSnapshot): string {
	return [
		describe(snapshot),
		`command: ${snapshot.command}`,
		`cwd: ${snapshot.cwd}`,
		snapshot.pid ? `pid: ${snapshot.pid}` : undefined,
		snapshot.errorText ? `error: ${snapshot.errorText}` : undefined,
		"",
		section("stdout", snapshot.stdout, STATUS_STDOUT_MAX, STATUS_STDOUT_LINES),
		section("stderr", snapshot.stderr, STATUS_STDERR_MAX, STATUS_STDERR_LINES),
	]
		.filter(Boolean)
		.join("\n");
}

function resultText(snapshot: TerminalSnapshot): string {
	return [
		`${glyph(snapshot.status)} Background terminal ${snapshot.id} "${snapshot.title}" ${snapshot.status}` +
			(snapshot.exitCode !== undefined && snapshot.exitCode !== null ? ` (exit ${snapshot.exitCode})` : "") +
			(snapshot.signal ? ` (signal ${snapshot.signal})` : ""),
		`command: ${snapshot.command}`,
		snapshot.errorText ? `error: ${snapshot.errorText}` : undefined,
		section("stdout", snapshot.stdout, RESULT_STDOUT_MAX, RESULT_STDOUT_LINES),
		section("stderr", snapshot.stderr, RESULT_STDERR_MAX, RESULT_STDERR_LINES, true),
	]
		.filter(Boolean)
		.join("\n");
}

export default function (pi: ExtensionAPI) {
	const manager = new TerminalManager();
	const herdrMetadata = new HerdrBackgroundMetadata();
	let uiCtx: ExtensionContext | undefined;
	let ownsHerdrMetadata = false;
	let shuttingDown = false;
	const delivery = new BackgroundTerminalDelivery(
		(snapshot) =>
			pi.sendMessage(
			{
				customType: RESULT_MESSAGE_TYPE,
				content: resultText(snapshot),
				display: true,
				details: {
					id: snapshot.id,
					title: snapshot.title,
					status: snapshot.status,
					exitCode: snapshot.exitCode ?? null,
				},
			},
			// followUp never interrupts a streaming turn; triggerTurn wakes an
			// idle agent so a finished build is noticed promptly.
			{ deliverAs: "followUp", triggerTurn: true },
			),
		{
			// Event ordering is advisory. Pi's live state is authoritative at the
			// actual handoff boundary, including queued steering/follow-up messages.
			canDeliver: () => Boolean(uiCtx?.isIdle() && !uiCtx.hasPendingMessages()),
		},
	);
	const refreshHerdrMetadata = () => {
		if (!ownsHerdrMetadata || shuttingDown) return;
		void herdrMetadata.setActive(manager.runningCount() > 0);
	};
	const refreshUi = () => {
		if (!uiCtx?.hasUI) return;
		const running = manager.list().filter((entry) => entry.status === "running");
		const status = backgroundTerminalStatus(running.length);
		uiCtx.ui.setStatus(UI_KEY, status ? uiCtx.ui.theme.fg("warning", status) : undefined);
		if (!running.length) return uiCtx.ui.setWidget(UI_KEY, undefined);
		uiCtx.ui.setWidget(
			UI_KEY,
			running.map((entry) => `● ${entry.id} ${entry.title}`),
		);
	};

	manager.onSettle((snapshot, consumed) => {
		refreshUi();
		refreshHerdrMetadata();
		// Lifecycle callbacks can race another extension starting a run. Consult
		// Pi's live state at the delivery boundary instead of trusting stale state.
		if (uiCtx?.isIdle()) delivery.setIdle();
		else delivery.setBusy();
		if (consumed) {
			delivery.consume(snapshot.id);
			return; // already shown via bg_status / bg_kill
		}
		delivery.enqueue(snapshot);
	});

	pi.on("session_start", async (_event, ctx) => {
		uiCtx = ctx;
		// Herdr's lifecycle integration is TUI-only. Headless child sessions may
		// inherit the pane environment but must never contend for its metadata.
		ownsHerdrMetadata = ctx.mode === "tui";
		if (ctx.isIdle()) delivery.setIdle();
		else delivery.setBusy();
		refreshUi();
		refreshHerdrMetadata();
	});
	pi.on("agent_start", async () => delivery.setBusy());
	// The agent has stopped working: now it is safe to hand over any results it
	// did not already collect itself. Another extension may already have started
	// a run by the time this callback executes, so verify Pi's live idle state.
	pi.on("agent_settled", async (_event, ctx) => {
		if (ctx.isIdle()) delivery.setIdle();
		else delivery.setBusy();
	});
	pi.on("session_shutdown", async () => {
		delivery.shutdown();
		shuttingDown = true;
		uiCtx?.ui.setStatus(UI_KEY, undefined);
		uiCtx?.ui.setWidget(UI_KEY, undefined);
		uiCtx = undefined;
		// Start process cleanup synchronously; best-effort display I/O must not
		// delay SIGTERM, and late settlement callbacks cannot reassert metadata.
		const dispose = manager.disposeAll();
		const clearMetadata = ownsHerdrMetadata ? herdrMetadata.shutdown() : Promise.resolve();
		await Promise.allSettled([dispose, clearMetadata]);
	});

	pi.registerTool({
		name: "bg_start",
		label: "Start Terminal",
		description:
			"Start a long-running shell command in a background terminal and return immediately. Commands run with Bash on macOS/Linux and ComSpec on Windows. Use this for dev servers, watchers, streaming builds, log tails — anything that should keep running while you continue working. Use the regular bash tool for commands that finish quickly. The command gets no stdin, so it must not expect interactive input.",
		promptSnippet: "Start and manage long-running shell commands without blocking the agent",
		promptGuidelines: [
			"Use bg_start for commands that run for a long time or continuously; start independent commands with separate bg_start calls in the same response so they run concurrently.",
			"On macOS and Linux, bg_start commands run under Bash, so guards may safely use `set -o pipefail` or `set -euo pipefail`.",
		],
		executionMode: "parallel",
		parameters: Type.Object(
			{
				command: Type.String({
					description: "Command to run with Bash on macOS/Linux or ComSpec on Windows.",
				}),
				title: Type.String({ description: "Short label shown in listings, e.g. 'vite dev'." }),
				working_dir: Type.Optional(
					Type.String({
						description: "Directory to run in, relative to the session cwd. Defaults to the session cwd.",
					}),
				),
			},
			{ additionalProperties: false },
		),
		async execute(_id, params: any, _signal, _onUpdate, ctx) {
			const cwd = path.resolve(ctx.cwd, params.working_dir ?? ".");
			const snapshot = manager.start({ command: params.command, title: params.title, cwd });
			refreshUi();
			refreshHerdrMetadata();
			return {
				content: [
					{
						type: "text" as const,
						text: [
							`Started ${snapshot.id} "${snapshot.title}"${snapshot.pid ? ` (pid ${snapshot.pid})` : ""} in ${cwd}.`,
							`Peek with bg_status id:"${snapshot.id}", stop with bg_kill. You will get a message when it exits.`,
						].join("\n"),
					},
				],
				details: { id: snapshot.id, title: snapshot.title, pid: snapshot.pid ?? null, cwd },
			};
		},
	});

	pi.registerTool({
		name: "bg_status",
		label: "Terminal Status",
		description:
			"Show a background terminal's status and its most recent output. Reading a finished terminal here counts as collecting its result, so you will not also get a separate completion message for it.",
		parameters: Type.Object(
			{ id: Type.String({ description: "Terminal id from bg_start / bg_list." }) },
			{
				additionalProperties: false,
			},
		),
		async execute(_id, params: any) {
			const snapshot = manager.get(params.id);
			if (!snapshot) {
				const known = manager.list().map((entry) => entry.id);
				throw new Error(
					`No background terminal ${params.id}.${known.length ? ` Known: ${known.join(", ")}` : ""}`,
				);
			}
			// Peeking a settled terminal consumes it: no duplicate follow-up.
			if (snapshot.status !== "running") {
				manager.markConsumed(snapshot.id);
				delivery.consume(snapshot.id);
			}
			return {
				content: [{ type: "text" as const, text: statusText(snapshot) }],
				details: { id: snapshot.id, status: snapshot.status, exitCode: snapshot.exitCode ?? null },
			};
		},
	});

	pi.registerTool({
		name: "bg_list",
		label: "List Terminals",
		description: "List all background terminals with status, age and output sizes.",
		parameters: Type.Object({}, { additionalProperties: false }),
		async execute() {
			const all = manager.list();
			const running = all.filter((entry) => entry.status === "running").length;
			return {
				content: [
					{
						type: "text" as const,
						text: all.length
							? [
									`Background terminals ${RUNTIME_VERSION}: ${all.length} tracked, ${running} running (max ${MAX_RUNNING})`,
									...all.map(describe),
								].join("\n")
							: `Background terminals ${RUNTIME_VERSION}: none. Start one with bg_start.`,
					},
				],
				details: { count: all.length, running },
			};
		},
	});

	pi.registerTool({
		name: "bg_kill",
		label: "Kill Terminal",
		description:
			"Stop one or more background terminals. Sends SIGTERM, escalating to SIGKILL if the process does not exit, and kills the whole process tree so child processes do not leak.",
		parameters: Type.Object(
			{
				ids: Type.Array(Type.String(), { minItems: 1, description: "Terminal ids to kill." }),
			},
			{ additionalProperties: false },
		),
		async execute(_id, params: any) {
			const lines: string[] = [];
			for (const id of params.ids) {
				try {
					const before = manager.get(id);
					if (before && before.status !== "running") {
						manager.markConsumed(id);
						delivery.consume(id);
						lines.push(`${id} was already ${before.status}`);
						continue;
					}
					const snapshot = await manager.kill(id);
					delivery.consume(id);
					lines.push(`${id} ${snapshot.status}${snapshot.signal ? ` (signal ${snapshot.signal})` : ""}`);
				} catch (error) {
					lines.push(`${id}: ${error instanceof Error ? error.message : String(error)}`);
				}
			}
			refreshUi();
			return {
				content: [{ type: "text" as const, text: lines.join("\n") }],
				details: { killed: params.ids.length },
			};
		},
	});

	pi.registerCommand("ps", {
		description: "List background terminals; '/ps kill <id>' stops one",
		handler: async (args: string, ctx: ExtensionContext) => {
			const argv = args.trim().split(/\s+/).filter(Boolean);
			if (argv[0] === "kill" && argv[1]) {
				try {
					const snapshot = await manager.kill(argv[1]);
					refreshUi();
					return ctx.ui.notify(`${snapshot.id} ${snapshot.status}`, "info");
				} catch (error) {
					return ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
				}
			}
			const all = manager.list();
			ctx.ui.notify(
				all.length
					? [`Background terminals ${RUNTIME_VERSION}`, ...all.map(describe)].join("\n")
					: `Background terminals ${RUNTIME_VERSION}: none`,
				"info",
			);
		},
	});
}
