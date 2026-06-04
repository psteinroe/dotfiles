/**
 * Project Loop Extension
 *
 * Adds a /loop command that repeatedly queues a follow-up prompt until the
 * agent calls signal_loop_success, or the user stops it with /loop stop.
 *
 * Usage:
 *   /loop                     Interactive preset picker
 *   /loop tests               Loop until the test suite passes
 *   /loop self                Loop until the agent decides the task is done
 *   /loop custom <condition>  Loop until a custom condition is satisfied
 *   /loop until <condition>   Alias for custom
 *   /loop status              Show current loop state
 *   /loop stop                Stop the loop
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

type LoopMode = "tests" | "custom" | "self";

type LoopState =
	| {
			active: true;
			mode: LoopMode;
			condition?: string;
			prompt: string;
			iteration: number;
			startedAt: number;
			lastTriggeredAt?: number;
	  }
	| {
			active: false;
			stoppedAt?: number;
			reason?: string;
	  };

type ParsedCommand =
	| { kind: "start"; state: LoopState & { active: true } }
	| { kind: "stop" }
	| { kind: "status" }
	| null;

const LOOP_STATE_ENTRY = "project-loop-state-v1";
const LEGACY_LOOP_STATE_ENTRY = "loop-state";

function conditionLabel(mode: LoopMode, condition?: string): string {
	switch (mode) {
		case "tests":
			return "tests pass";
		case "custom":
			return condition?.trim() || "custom condition is met";
		case "self":
			return "task is done";
	}
}

function buildPrompt(mode: LoopMode, condition?: string): string {
	const label = conditionLabel(mode, condition);

	switch (mode) {
		case "tests":
			return [
				"Automatic loop iteration.",
				"Run the relevant test suite. If all tests pass, call signal_loop_success.",
				"If tests fail, fix the failure and keep working toward passing tests.",
				"Do not call signal_loop_success until tests pass.",
			].join(" ");
		case "custom":
			return [
				"Automatic loop iteration.",
				`Continue until this condition is satisfied: ${label}.`,
				"If the condition is now satisfied, call signal_loop_success.",
				"Otherwise take the next concrete step toward satisfying it.",
			].join(" ");
		case "self":
			return [
				"Automatic loop iteration.",
				"Continue working autonomously on the current task.",
				"When the task is complete, call signal_loop_success.",
				"Otherwise take the next concrete step.",
			].join(" ");
	}
}

function summarizeState(state: LoopState): string {
	if (!state.active) return state.reason ? `Loop inactive (${state.reason}).` : "Loop inactive.";
	return `Loop active: ${conditionLabel(state.mode, state.condition)}; iteration ${state.iteration}.`;
}

function updateWidget(ctx: ExtensionContext, state: LoopState): void {
	if (!ctx.hasUI) return;

	if (!state.active) {
		ctx.ui.setWidget("project-loop", undefined);
		return;
	}

	const label = conditionLabel(state.mode, state.condition);
	const summary = label.length > 72 ? `${label.slice(0, 69)}...` : label;
	ctx.ui.setWidget("project-loop", [
		ctx.ui.theme.fg("accent", `↻ Loop active`),
		ctx.ui.theme.fg("dim", `until ${summary} · iteration ${state.iteration}`),
	]);
}

function coercePersistedState(data: unknown): LoopState | null {
	const state = data as Partial<LoopState & { loopCount?: number }> | undefined;
	if (!state || typeof state !== "object") return null;
	if (!state.active) return { active: false };
	if (!state.mode || !state.prompt) return null;

	return {
		active: true,
		mode: state.mode,
		condition: state.condition,
		prompt: state.prompt,
		iteration: typeof state.iteration === "number" ? state.iteration : state.loopCount ?? 0,
		startedAt: typeof state.startedAt === "number" ? state.startedAt : Date.now(),
		lastTriggeredAt: state.lastTriggeredAt,
	};
}

function latestPersistedState(ctx: ExtensionContext): LoopState {
	const entries = ctx.sessionManager.getBranch();
	for (let i = entries.length - 1; i >= 0; i--) {
		const entry = entries[i] as { type?: string; customType?: string; data?: unknown };
		if (
			entry.type === "custom" &&
			(entry.customType === LOOP_STATE_ENTRY || entry.customType === LEGACY_LOOP_STATE_ENTRY)
		) {
			const state = coercePersistedState(entry.data);
			if (state) return state;
		}
	}
	return { active: false };
}

function wasLastAssistantAborted(messages: Array<{ role?: string; stopReason?: string }>): boolean {
	for (let i = messages.length - 1; i >= 0; i--) {
		const message = messages[i];
		if (message?.role === "assistant") return message.stopReason === "aborted";
	}
	return false;
}

function parseCommand(args: string | undefined): ParsedCommand {
	const text = args?.trim();
	if (!text) return null;

	const [rawMode = "", ...rest] = text.split(/\s+/);
	const mode = rawMode.toLowerCase();
	const condition = rest.join(" ").trim();

	if (["stop", "end", "off", "cancel"].includes(mode)) return { kind: "stop" };
	if (["status", "state"].includes(mode)) return { kind: "status" };

	if (mode === "tests" || mode === "test") {
		return {
			kind: "start",
			state: {
				active: true,
				mode: "tests",
				prompt: buildPrompt("tests"),
				iteration: 0,
				startedAt: Date.now(),
			},
		};
	}

	if (mode === "self" || mode === "auto") {
		return {
			kind: "start",
			state: {
				active: true,
				mode: "self",
				prompt: buildPrompt("self"),
				iteration: 0,
				startedAt: Date.now(),
			},
		};
	}

	if (mode === "custom" || mode === "until") {
		if (!condition) return null;
		return {
			kind: "start",
			state: {
				active: true,
				mode: "custom",
				condition,
				prompt: buildPrompt("custom", condition),
				iteration: 0,
				startedAt: Date.now(),
			},
		};
	}

	return null;
}

async function promptForLoopState(ctx: ExtensionContext): Promise<(LoopState & { active: true }) | null> {
	if (!ctx.hasUI) return null;

	const preset = await ctx.ui.select("Start loop", [
		"tests — until tests pass",
		"custom — until a condition is met",
		"self — until the agent decides it is done",
	]);

	if (!preset) return null;

	if (preset.startsWith("tests")) {
		return {
			active: true,
			mode: "tests",
			prompt: buildPrompt("tests"),
			iteration: 0,
			startedAt: Date.now(),
		};
	}

	if (preset.startsWith("self")) {
		return {
			active: true,
			mode: "self",
			prompt: buildPrompt("self"),
			iteration: 0,
			startedAt: Date.now(),
		};
	}

	const condition = (await ctx.ui.editor("Loop until this condition is satisfied:", ""))?.trim();
	if (!condition) return null;

	return {
		active: true,
		mode: "custom",
		condition,
		prompt: buildPrompt("custom", condition),
		iteration: 0,
		startedAt: Date.now(),
	};
}

export default function projectLoopExtension(pi: ExtensionAPI): void {
	let loopState: LoopState = { active: false };

	function persist(state: LoopState): void {
		pi.appendEntry(LOOP_STATE_ENTRY, state);
	}

	function setState(ctx: ExtensionContext, state: LoopState): void {
		loopState = state;
		persist(state);
		updateWidget(ctx, state);
	}

	function stop(ctx: ExtensionContext, reason = "stopped"): void {
		setState(ctx, { active: false, stoppedAt: Date.now(), reason });
		ctx.ui.notify("Loop stopped", "info");
	}

	function triggerNextIteration(ctx: ExtensionContext): void {
		if (!loopState.active) return;
		if (ctx.hasPendingMessages()) return;

		const nextState: LoopState = {
			...loopState,
			iteration: loopState.iteration + 1,
			lastTriggeredAt: Date.now(),
		};
		setState(ctx, nextState);

		pi.sendMessage(
			{
				customType: "loop",
				content: nextState.prompt,
				display: true,
				details: {
					mode: nextState.mode,
					condition: nextState.condition,
					iteration: nextState.iteration,
				},
			},
			{ deliverAs: "followUp", triggerTurn: true },
		);
	}

	pi.registerTool({
		name: "signal_loop_success",
		label: "Signal Loop Success",
		description:
			"Stop the active /loop automation when its breakout condition is satisfied. Only call this after the loop condition is actually satisfied.",
		promptSnippet: "Stop an active /loop automation after the breakout condition has been met",
		promptGuidelines: [
			"Use signal_loop_success only when an active /loop prompt tells you to stop and the loop breakout condition is satisfied.",
		],
		parameters: Type.Object({}),
		async execute(_toolCallId, _params, _signal, _onUpdate, ctx) {
			if (!loopState.active) {
				return {
					content: [{ type: "text", text: "No active loop is running." }],
					details: { active: false },
				};
			}

			setState(ctx, { active: false, stoppedAt: Date.now(), reason: "success" });
			ctx.ui.notify("Loop completed", "info");

			return {
				content: [{ type: "text", text: "Loop stopped successfully." }],
				details: { active: false, reason: "success" },
			};
		},
	});

	pi.registerCommand("loop", {
		description: "Repeat follow-up turns until tests pass, a condition is met, or the agent is done",
		handler: async (args, ctx) => {
			const parsed = parseCommand(args);

			if (parsed?.kind === "stop") {
				stop(ctx, "stopped by user");
				return;
			}

			if (parsed?.kind === "status") {
				ctx.ui.notify(summarizeState(loopState), loopState.active ? "info" : "warning");
				return;
			}

			let nextState = parsed?.kind === "start" ? parsed.state : null;
			if (!nextState) nextState = await promptForLoopState(ctx);

			if (!nextState) {
				ctx.ui.notify("Usage: /loop tests | /loop self | /loop custom <condition> | /loop stop", "warning");
				return;
			}

			if (loopState.active) {
				const replace = ctx.hasUI
					? await ctx.ui.confirm("Replace active loop?", summarizeState(loopState))
					: true;
				if (!replace) return;
			}

			setState(ctx, nextState);
			ctx.ui.notify(summarizeState(nextState), "info");
			triggerNextIteration(ctx);
		},
	});

	pi.on("agent_end", async (event, ctx) => {
		if (!loopState.active) return;

		if (ctx.hasUI && wasLastAssistantAborted(event.messages)) {
			const shouldStop = await ctx.ui.confirm(
				"Stop active loop?",
				"The last assistant turn was aborted. Stop the loop instead of continuing?",
			);
			if (shouldStop) {
				stop(ctx, "aborted by user");
				return;
			}
		}

		triggerNextIteration(ctx);
	});

	pi.on("session_start", async (_event, ctx) => {
		loopState = latestPersistedState(ctx);
		updateWidget(ctx, loopState);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		updateWidget(ctx, { active: false });
	});
}
