import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import path from "node:path";

const NVIM_SERVER = process.env.NVIM;
const BRAILLE_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

let currentModel: string | undefined;
let sessionName: string | undefined;
let isWorking = false;
let currentTool: string | undefined;
let remoteTitle = process.env.RDEV_REMOTE_TITLE === "1";
let spinnerTimer: ReturnType<typeof setInterval> | undefined;
let completionTimer: ReturnType<typeof setTimeout> | undefined;
let frameIndex = 0;

function vimSingleQuoted(value: string): string {
	return `'${value.replace(/'/g, "''")}'`;
}

function setNvimTitle(title: string): void {
	if (!NVIM_SERVER) {
		return;
	}

	const lua = `require("config.status-title").set_title(${JSON.stringify(title)})`;
	const child = spawn("nvim", ["--server", NVIM_SERVER, "--remote-expr", `luaeval(${vimSingleQuoted(lua)})`], {
		stdio: "ignore",
	});

	child.on("error", () => {
		// Ignore missing nvim binary/socket failures.
	});
	child.unref();
}

function remoteTitlePrefix(): string {
	return remoteTitle ? process.env.RDEV_TITLE_PREFIX ?? "🌐 " : "";
}

function prefixedTitle(title: string): string {
	const prefix = remoteTitlePrefix();
	return prefix && !title.startsWith(prefix) ? `${prefix}${title}` : title;
}

function argvHasRemoteSshFlag(): boolean {
	return process.argv.some((arg) => arg === "--remote-ssh" || arg.startsWith("--remote-ssh="));
}

function buildTitle(extra?: string): string {
	const segments: string[] = ["π"];
	segments.push(path.basename(process.cwd()));
	if (sessionName) segments.push(sessionName);
	if (extra) segments.push(extra);
	else if (currentModel) segments.push(currentModel);
	return prefixedTitle(segments.join(" · "));
}

function startSpinner() {
	if (spinnerTimer) clearInterval(spinnerTimer);
	if (completionTimer) {
		clearTimeout(completionTimer);
		completionTimer = undefined;
	}
	isWorking = true;
	currentTool = undefined;
	frameIndex = 0;
	spinnerTimer = setInterval(() => {
		const frame = BRAILLE_FRAMES[frameIndex % BRAILLE_FRAMES.length];
		frameIndex++;
		const extra = currentTool ?? undefined;
		setNvimTitle(`${frame} ${buildTitle(extra)}`);
	}, 80);
}

function stopSpinner() {
	isWorking = false;
	currentTool = undefined;
	if (spinnerTimer) {
		clearInterval(spinnerTimer);
		spinnerTimer = undefined;
	}
	setNvimTitle(buildTitle());
	completionTimer = setTimeout(() => {
		completionTimer = undefined;
	}, 800);
}

export default function statusTitleExtension(pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		currentModel = ctx.model?.id;
		sessionName = pi.getSessionName();
		try {
			remoteTitle = remoteTitle || Boolean(pi.getFlag("remote-ssh")) || argvHasRemoteSshFlag();
		} catch {
			remoteTitle = remoteTitle || argvHasRemoteSshFlag();
		}
		setNvimTitle(buildTitle());
	});

	pi.on("model_select", async (event, ctx) => {
		if (!ctx.hasUI) return;
		currentModel = event.model.id;
		if (!isWorking) setNvimTitle(buildTitle());
	});

	pi.on("agent_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		startSpinner();
	});

	pi.on("agent_end", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		stopSpinner();
	});

	pi.on("tool_execution_start", async (event) => {
		currentTool = event.toolName;
	});

	pi.on("tool_execution_end", async () => {
		currentTool = undefined;
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		if (spinnerTimer) clearInterval(spinnerTimer);
		if (completionTimer) clearTimeout(completionTimer);
		spinnerTimer = undefined;
		completionTimer = undefined;
	});
}
