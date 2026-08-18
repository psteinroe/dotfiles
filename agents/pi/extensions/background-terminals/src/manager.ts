/**
 * Background terminal manager.
 *
 * Long-running shell commands (dev servers, watchers, streaming builds) that
 * keep running while the agent continues working. A terminal receives **no
 * stdin** — it is launched with `stdio: ["ignore", ...]` so anything waiting on
 * input sees EOF immediately rather than hanging forever.
 *
 * Clean-room plain-TypeScript implementation of the design in
 * davis7dotsh/my-pi-setup's background-terminals extension (that one is built
 * on Effect v4 beta; we deliberately carry no such dependency). The constants
 * and edge-case handling below follow its published behavior, which was read
 * from source rather than guessed.
 *
 * Load-bearing invariants:
 *
 * - **Own process group on POSIX** (`detached: true`) so `kill(-pid)` reaps the
 *   whole tree. A dev server that spawns children must not leak them.
 * - **Settles exactly once.** Status is decided by the first of error/exit/close
 *   to complete, then frozen; later events are ignored.
 * - **Bounded memory.** Each stream retains at most 2 MiB, evicting whole
 *   chunks from the head. A single oversized write is sliced on a UTF-8
 *   boundary so we never cut a multi-byte character in half.
 * - **Nothing outlives the session.** Disposal SIGTERMs then SIGKILLs every
 *   tree; a Pi restart must never leave an orphaned dev server behind.
 */

import { type ChildProcess, spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/** Max concurrently running terminals. */
export const MAX_RUNNING = 8;
/** Max tracked entries; oldest settled are pruned beyond this. */
export const MAX_TRACKED = 32;
/** In-memory retention per stream. */
export const RETAINED_PER_STREAM = 2 * 1024 * 1024;
/** Gap between SIGTERM and SIGKILL. */
const FORCE_KILL_AFTER_MS = 2_000;
/** Wait for 'close' after SIGKILL before giving up. */
const POST_KILL_WAIT_MS = 500;
/** Grace for pipes to close after the shell exits (orphan holding stdout). */
const SETTLE_GRACE_MS = 1_000;
/** Upper bound on a single terminate+settle. */
const STOP_TIMEOUT_MS = 5_000;
/** Error text cap. */
const ERROR_TEXT_MAX = 4_096;
/** Title cap. */
const TITLE_MAX = 80;

export type TerminalStatus = "running" | "done" | "failed" | "killed";

export interface StreamView {
	/** Retained (possibly head-trimmed) text. */
	text: string;
	/** Every byte ever seen on this stream. */
	totalBytes: number;
	/** Bytes dropped from the head of the retained view. */
	truncatedBytes: number;
}

export interface TerminalSnapshot {
	id: string;
	command: string;
	title: string;
	cwd: string;
	pid?: number;
	status: TerminalStatus;
	createdAt: number;
	settledAt?: number;
	exitCode?: number | null;
	signal?: string | null;
	errorText?: string;
	stdout: StreamView;
	stderr: StreamView;
}

/**
 * Bounded output buffer with whole-chunk head eviction.
 *
 * Eviction drops entire chunks rather than slicing, which keeps the common path
 * cheap and cannot split a character. The one exception is a single write larger
 * than the cap: there we must slice, and we advance past UTF-8 continuation
 * bytes (`0b10xxxxxx`) so the retained tail starts on a real code point. That
 * can retain slightly *fewer* bytes than the cap, never more.
 */
class OutputBuffer {
	private chunks: string[] = [];
	private retained = 0;
	private total = 0;
	private dropped = 0;
	private cache?: string;
	private readonly max: number;

	constructor(max = RETAINED_PER_STREAM) {
		this.max = max;
	}

	push(chunk: string): void {
		if (!chunk) return;
		const bytes = Buffer.byteLength(chunk, "utf8");
		this.total += bytes;

		if (bytes > this.max) {
			// Oversized single write: keep only the tail, cut on a code point.
			this.dropped += this.retained;
			this.chunks = [];
			this.retained = 0;
			const raw = Buffer.from(chunk, "utf8");
			let start = raw.length - this.max;
			while (start < raw.length && (raw[start]! & 0xc0) === 0x80) start++;
			this.dropped += start;
			const tail = raw.subarray(start).toString("utf8");
			this.chunks.push(tail);
			this.retained = Buffer.byteLength(tail, "utf8");
			this.cache = undefined;
			return;
		}

		this.chunks.push(chunk);
		this.retained += bytes;
		while (this.retained > this.max && this.chunks.length > 1) {
			const head = this.chunks.shift()!;
			const headBytes = Buffer.byteLength(head, "utf8");
			this.retained -= headBytes;
			this.dropped += headBytes;
		}
		this.cache = undefined;
	}

	view(): StreamView {
		if (this.cache === undefined) this.cache = this.chunks.join("");
		return { text: this.cache, totalBytes: this.total, truncatedBytes: this.dropped };
	}
}

interface Entry {
	snapshot: TerminalSnapshot;
	child?: ChildProcess;
	stdout: OutputBuffer;
	stderr: OutputBuffer;
	/** Shell exited, but pipes may still be open. */
	exited: boolean;
	/** stdio fully closed. */
	closed: boolean;
	/** A spawn-level error fired ('error' event). */
	errored: boolean;
	/** A kill was requested while still running. */
	killRequested: boolean;
	/** Someone already read the terminal result, so suppress auto-delivery. */
	consumed: boolean;
	exitTimer?: NodeJS.Timeout;
	settleWaiters: Array<() => void>;
}

const bounded = (text: string): string =>
	text.length > ERROR_TEXT_MAX ? `${text.slice(0, ERROR_TEXT_MAX - 1)}…` : text;

export class TerminalManager {
	private readonly entries = new Map<string, Entry>();
	private counter = 0;
	private disposed = false;
	/** Slots claimed synchronously so parallel starts cannot race past the cap. */
	private reserved = 0;
	private onSettleHook?: (snapshot: TerminalSnapshot, consumed: boolean) => void;

	onSettle(hook: (snapshot: TerminalSnapshot, consumed: boolean) => void): void {
		this.onSettleHook = hook;
	}

	runningCount(): number {
		let count = 0;
		for (const [, entry] of this.entries) if (entry.snapshot.status === "running") count++;
		return count;
	}

	list(): TerminalSnapshot[] {
		return [...this.entries.values()].map((entry) => this.snapshot(entry));
	}

	get(id: string): TerminalSnapshot | undefined {
		const entry = this.entries.get(id);
		return entry ? this.snapshot(entry) : undefined;
	}

	/** Mark a result as seen so it is not also auto-delivered. */
	markConsumed(id: string): void {
		const entry = this.entries.get(id);
		if (entry) entry.consumed = true;
	}

	private snapshot(entry: Entry): TerminalSnapshot {
		return { ...entry.snapshot, stdout: entry.stdout.view(), stderr: entry.stderr.view() };
	}

	start(options: { command: string; title: string; cwd: string }): TerminalSnapshot {
		if (this.disposed) throw new Error("Background terminals are shutting down");
		const command = options.command.trim();
		if (!command) throw new Error("command must not be empty");
		// Reserve synchronously: two parallel bg_start calls must not both pass.
		if (this.runningCount() + this.reserved >= MAX_RUNNING) {
			throw new Error(
				`Max ${MAX_RUNNING} background terminals can run at once. Kill one with bg_kill before starting another.`,
			);
		}
		this.reserved++;
		try {
			const stat = fs.statSync(options.cwd);
			if (!stat.isDirectory()) throw new Error(`working_dir is not a directory: ${options.cwd}`);
		} catch (error) {
			this.reserved--;
			if (error instanceof Error && "code" in error && (error as { code?: string }).code === "ENOENT") {
				throw new Error(`working_dir does not exist: ${options.cwd}`);
			}
			throw error;
		}

		const id = `bt-${++this.counter}`;
		const title = options.title.replace(/\s+/g, " ").trim().slice(0, TITLE_MAX) || "terminal";
		const entry: Entry = {
			snapshot: {
				id,
				command,
				title,
				cwd: options.cwd,
				status: "running",
				createdAt: Date.now(),
				stdout: { text: "", totalBytes: 0, truncatedBytes: 0 },
				stderr: { text: "", totalBytes: 0, truncatedBytes: 0 },
			},
			stdout: new OutputBuffer(),
			stderr: new OutputBuffer(),
			exited: false,
			closed: false,
			errored: false,
			killRequested: false,
			consumed: false,
			settleWaiters: [],
		};

		try {
			const isWindows = process.platform === "win32";
			const shell = isWindows ? (process.env.ComSpec ?? "cmd.exe") : "/bin/sh";
			const args = isWindows ? ["/d", "/s", "/c", command] : ["-c", command];
			const child = spawn(shell, args, {
				cwd: options.cwd,
				env: process.env,
				// No stdin: anything prompting sees EOF instead of hanging.
				stdio: ["ignore", "pipe", "pipe"],
				// Own process group on POSIX so the whole tree can be killed.
				detached: !isWindows,
			});
			entry.child = child;
			entry.snapshot.pid = child.pid;

			child.stdout?.setEncoding("utf8");
			child.stderr?.setEncoding("utf8");
			child.stdout?.on("data", (chunk: string) => entry.stdout.push(chunk));
			child.stderr?.on("data", (chunk: string) => entry.stderr.push(chunk));

			child.on("error", (error) => {
				entry.errored = true;
				entry.exited = true;
				entry.snapshot.errorText = bounded(error.message);
				this.settle(entry);
			});
			child.on("exit", (code, signal) => {
				entry.exited = true;
				// Only trust exit codes when no spawn error fired: after an
				// 'error', Node reports errno-ish codes on close.
				if (!entry.errored) {
					entry.snapshot.exitCode = code;
					entry.snapshot.signal = signal;
				}
				// The shell exited but a grandchild may still hold the pipes open.
				// Give it a grace period, then force the issue.
				entry.exitTimer = setTimeout(() => {
					if (entry.snapshot.status === "running" && !entry.closed) {
						entry.snapshot.errorText ??= "stdio did not close after exit; output may be incomplete";
						this.killTree(entry, "SIGKILL");
						this.settle(entry);
					}
				}, SETTLE_GRACE_MS);
				entry.exitTimer.unref?.();
			});
			child.on("close", (code, signal) => {
				entry.closed = true;
				if (!entry.errored) {
					entry.snapshot.exitCode ??= code;
					entry.snapshot.signal ??= signal;
				}
				this.settle(entry);
			});
		} catch (error) {
			this.reserved--;
			throw error;
		}

		this.entries.set(id, entry);
		this.reserved--;
		this.prune();
		return this.snapshot(entry);
	}

	/**
	 * Decide the terminal state, exactly once.
	 *
	 * `killRequested` only wins when the shell had not already exited: a process
	 * that finished on its own microseconds before a kill request should report
	 * its real exit code, not "killed".
	 */
	private settle(entry: Entry): void {
		if (entry.snapshot.status !== "running") return;
		if (entry.exitTimer) {
			clearTimeout(entry.exitTimer);
			entry.exitTimer = undefined;
		}
		const snap = entry.snapshot;
		snap.settledAt = Date.now();
		snap.status =
			entry.killRequested && !entry.exited
				? "killed"
				: entry.errored
					? "failed"
					: snap.exitCode === 0
						? "done"
						: snap.signal && entry.killRequested
							? "killed"
							: "failed";
		snap.stdout = entry.stdout.view();
		snap.stderr = entry.stderr.view();
		for (const waiter of entry.settleWaiters.splice(0)) waiter();
		if (!this.disposed) this.onSettleHook?.(this.snapshot(entry), entry.consumed);
	}

	/** Kill the whole process group, falling back to the direct child. */
	private killTree(entry: Entry, signal: NodeJS.Signals): void {
		const child = entry.child;
		const pid = child?.pid;
		if (!child || !pid) return;
		try {
			if (process.platform === "win32") {
				const args = ["/pid", String(pid), "/T"];
				if (signal === "SIGKILL") args.push("/F");
				const killer = spawn("taskkill", args, { stdio: "ignore", windowsHide: true });
				killer.on("error", () => {
					try {
						child.kill(signal);
					} catch {
						/* already gone */
					}
				});
				killer.unref();
				return;
			}
			// Negative pid targets the group created by detached: true.
			process.kill(-pid, signal);
		} catch {
			try {
				child.kill(signal);
			} catch {
				/* already gone */
			}
		}
	}

	/** SIGTERM, then SIGKILL if it does not close in time. */
	async kill(id: string): Promise<TerminalSnapshot> {
		const entry = this.entries.get(id);
		if (!entry) throw new Error(`No background terminal ${id}. Use bg_list to see known ids.`);
		if (entry.snapshot.status !== "running") return this.snapshot(entry);
		entry.killRequested = true;
		entry.consumed = true;

		const settled = new Promise<void>((resolve) => entry.settleWaiters.push(resolve));
		this.killTree(entry, "SIGTERM");
		const escalated = await Promise.race([
			settled.then(() => true),
			new Promise<false>((resolve) => {
				const timer = setTimeout(() => resolve(false), FORCE_KILL_AFTER_MS);
				timer.unref?.();
			}),
		]);
		if (!escalated) {
			this.killTree(entry, "SIGKILL");
			await Promise.race([
				settled,
				new Promise<void>((resolve) => {
					const timer = setTimeout(resolve, POST_KILL_WAIT_MS);
					timer.unref?.();
				}),
			]);
			// Nothing closed the pipes; record what we know and stop waiting.
			if (entry.snapshot.status === "running") {
				entry.snapshot.errorText ??= "process did not close after SIGKILL";
				this.settle(entry);
			}
		}
		return this.snapshot(entry);
	}

	/** Drop oldest settled entries beyond the tracking cap. */
	private prune(): void {
		if (this.entries.size <= MAX_TRACKED) return;
		const settled = [...this.entries.entries()]
			.filter(([, entry]) => entry.snapshot.status !== "running")
			.sort((a, b) => (a[1].snapshot.settledAt ?? 0) - (b[1].snapshot.settledAt ?? 0));
		for (const [id] of settled) {
			if (this.entries.size <= MAX_TRACKED) break;
			this.entries.delete(id);
		}
	}

	/**
	 * Kill everything. A live dev server must never outlive the Pi session that
	 * started it, so this runs on session shutdown and is bounded so it cannot
	 * hang exit.
	 */
	async disposeAll(): Promise<number> {
		this.disposed = true;
		const running = [...this.entries.values()].filter((entry) => entry.snapshot.status === "running");
		await Promise.race([
			Promise.all(
				running.map(async (entry) => {
					entry.killRequested = true;
					const settled = new Promise<void>((resolve) => entry.settleWaiters.push(resolve));
					this.killTree(entry, "SIGTERM");
					const closed = await Promise.race([
						settled.then(() => true),
						new Promise<false>((resolve) => {
							const timer = setTimeout(() => resolve(false), FORCE_KILL_AFTER_MS);
							timer.unref?.();
						}),
					]);
					if (!closed) this.killTree(entry, "SIGKILL");
				}),
			),
			new Promise<void>((resolve) => {
				const timer = setTimeout(resolve, STOP_TIMEOUT_MS);
				timer.unref?.();
			}),
		]);
		return running.length;
	}
}

/** Human-readable byte size. */
export function formatBytes(bytes: number): string {
	if (bytes < 1024) return `${bytes}B`;
	if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
	return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

/** Elapsed time, compact. */
export function formatElapsed(from: number, to = Date.now()): string {
	const seconds = Math.max(0, Math.round((to - from) / 1000));
	if (seconds < 60) return `${seconds}s`;
	const minutes = Math.floor(seconds / 60);
	if (minutes < 60) return `${minutes}m${seconds % 60}s`;
	return `${Math.floor(minutes / 60)}h${minutes % 60}m`;
}

/** Tail-truncate for model output: the end of a log is what matters. */
export function tail(text: string, maxBytes: number, maxLines: number): { text: string; truncated: boolean } {
	let out = text;
	let truncated = false;
	const lines = out.split("\n");
	if (lines.length > maxLines) {
		out = lines.slice(-maxLines).join("\n");
		truncated = true;
	}
	if (Buffer.byteLength(out, "utf8") > maxBytes) {
		const raw = Buffer.from(out, "utf8");
		let start = raw.length - maxBytes;
		while (start < raw.length && (raw[start]! & 0xc0) === 0x80) start++;
		out = raw.subarray(start).toString("utf8");
		truncated = true;
	}
	return { text: out, truncated };
}

/** Where spilled full logs would go, if we add spill later. */
export function spillRoot(): string {
	return path.join(os.tmpdir(), "pi-bg-terminals");
}
