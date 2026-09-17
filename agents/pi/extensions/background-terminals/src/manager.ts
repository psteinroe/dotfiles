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
 * - **Process groups plus containment scans on POSIX** (`detached: true`):
 *   signaling `kill(-pid)` is the fast path, while scans catch escaped or
 *   reparented normal descendants. `kill(-pid)` alone does not reap the whole
 *   tree.
 * - **Settles exactly once.** Status is decided by the first of error/exit/close
 *   to complete, then frozen; later events are ignored.
 * - **Bounded memory.** Each stream retains at most 512 KiB, evicting whole
 *   chunks from the head. A single oversized write is sliced on a UTF-8
 *   boundary so we never cut a multi-byte character in half.
 * - **Nothing outlives the session.** Disposal SIGTERMs then SIGKILLs every
 *   tree; a Pi restart must never leave an orphaned dev server behind.
 */

import { type ChildProcess, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/** Max concurrently running terminals. */
export const MAX_RUNNING = 8;
/** Max tracked entries; oldest settled are pruned beyond this. */
export const MAX_TRACKED = 32;
/** In-memory retention per stream. */
export const RETAINED_PER_STREAM = 512 * 1024;
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
/** Name of the inherited, per-entry process containment label. */
const CONTAINMENT_ENV = "PI_BACKGROUND_TERMINAL_TOKEN";
/** A process scan must not make shutdown unbounded. */
const MARKER_SCAN_TIMEOUT_MS = 500;
/** Do not allow an unexpectedly large ps listing to consume unbounded memory. */
const MAX_PS_OUTPUT_BYTES = 16 * 1024 * 1024;

interface ProcessIdentity {
	pid: number;
	/** A start-time signature from the same process snapshot as the PID. */
	startSignature: string;
}

interface MarkerScan {
	pids: Set<number>;
	/** Identities for every PID in `pids`, from this scan. */
	identities: Map<number, ProcessIdentity>;
	/** Descendants found through PPID traversal, retained across rescans. */
	discoveredPids: Set<number>;
	/** Stable identities for retained macOS descendants. */
	discoveredIdentities: Map<number, ProcessIdentity>;
	/** The root identity observed in this snapshot, if it was eligible to seed traversal. */
	rootIdentity?: ProcessIdentity;
	complete: boolean;
}

const isSafePid = (pid: number): boolean =>
	Number.isSafeInteger(pid) && pid > 1 && pid !== process.pid;

const errorCode = (error: unknown): string | undefined =>
	error && typeof error === "object" && "code" in error ? String((error as { code?: unknown }).code) : undefined;

const markerInEnvironment = (environment: Buffer, token: string): boolean => {
	const marker = Buffer.from(`${CONTAINMENT_ENV}=${token}`);
	let start = 0;
	while (start < environment.length) {
		const end = environment.indexOf(0, start);
		const valueEnd = end === -1 ? environment.length : end;
		if (environment.subarray(start, valueEnd).equals(marker)) return true;
		start = valueEnd + 1;
	}
	return false;
};

const emptyMarkerScan = (complete = false): MarkerScan => ({
	pids: new Set(),
	identities: new Map(),
	discoveredPids: new Set(),
	discoveredIdentities: new Map(),
	complete,
});

interface LinuxProcess {
	pid: number;
	ppid: number;
}

async function scanLinuxProcesses(
	token: string,
	previouslyDiscoveredPids: Set<number>,
): Promise<MarkerScan> {
	const result = emptyMarkerScan();
	const uid = process.getuid?.();
	if (uid === undefined) return result;
	result.complete = true;
	const deadline = Date.now() + MARKER_SCAN_TIMEOUT_MS;
	const controller = new AbortController();
	const timeout = setTimeout(() => controller.abort(), MARKER_SCAN_TIMEOUT_MS);
	const processes: LinuxProcess[] = [];
	const markerPids = new Set<number>();
	const childrenByPpid = new Map<number, LinuxProcess[]>();
	const timedOut = (): boolean => Date.now() >= deadline;
	try {
		let names: string[];
		try {
			names = await fs.promises.readdir("/proc");
		} catch {
			result.complete = false;
			return result;
		}
		for (const name of names) {
			if (timedOut()) {
				result.complete = false;
				return result;
			}
			if (!/^\d+$/.test(name)) continue;
			const pid = Number(name);
			if (!isSafePid(pid)) continue;
			let status: Buffer;
			try {
				status = await fs.promises.readFile(`/proc/${name}/status`, { signal: controller.signal });
			} catch (error) {
				// A process can disappear between readdir and readFile. Other status
				// failures mean the ancestry snapshot is not complete.
				if (errorCode(error) !== "ENOENT") result.complete = false;
				if (errorCode(error) === "ABORT_ERR") return result;
				continue;
			}
			const text = status.toString("utf8");
			const uidMatch = /^Uid:\s+(\d+)/m.exec(text);
			const ppidMatch = /^PPid:\s+(\d+)/m.exec(text);
			if (!uidMatch || !ppidMatch) {
				result.complete = false;
				continue;
			}
			if (Number(uidMatch[1]) !== uid) continue;
			const row = { pid, ppid: Number(ppidMatch[1]) };
			processes.push(row);
			const children = childrenByPpid.get(row.ppid) ?? [];
			children.push(row);
			childrenByPpid.set(row.ppid, children);
			try {
				const environment = await fs.promises.readFile(`/proc/${name}/environ`, { signal: controller.signal });
				if (markerInEnvironment(environment, token)) markerPids.add(pid);
			} catch (error) {
				// Same-UID processes may deliberately make environ unreadable. That
				// is expected for unrelated processes; PPID traversal below still
				// catches an inaccessible descendant of a known marker.
				const code = errorCode(error);
				if (code === "ABORT_ERR") {
					result.complete = false;
					return result;
				}
				if (code !== "ENOENT" && code !== "EACCES" && code !== "EPERM") result.complete = false;
			}
		}
		if (timedOut()) {
			result.complete = false;
			return result;
		}

		const pending = [...markerPids];
		for (const pid of previouslyDiscoveredPids) {
			if (processes.some((row) => row.pid === pid)) {
				result.pids.add(pid);
				result.discoveredPids.add(pid);
				pending.push(pid);
			}
		}
		for (const pid of markerPids) {
			result.pids.add(pid);
		}
		for (let index = 0; index < pending.length; index++) {
			if (timedOut()) {
				result.complete = false;
				return result;
			}
			for (const row of childrenByPpid.get(pending[index]!) ?? []) {
				if (result.discoveredPids.has(row.pid)) continue;
				result.discoveredPids.add(row.pid);
				result.pids.add(row.pid);
				pending.push(row.pid);
			}
		}
		if (timedOut()) result.complete = false;
		return result;
	} finally {
		clearTimeout(timeout);
	}
}

interface MacProcess {
	uid: number;
	pid: number;
	ppid: number;
	command: string;
	identity: ProcessIdentity;
}

const sameIdentity = (left: ProcessIdentity | undefined, right: ProcessIdentity | undefined): boolean =>
	left !== undefined && right !== undefined && left.pid === right.pid && left.startSignature === right.startSignature;

async function scanMacProcesses(
	token: string,
	rootPid: number | undefined,
	rootIdentity: ProcessIdentity | undefined,
	allowRootSeed: boolean,
	previouslyDiscoveredPids: Set<number>,
	previouslyDiscoveredIdentities: Map<number, ProcessIdentity>,
): Promise<MarkerScan> {
	const result = emptyMarkerScan();
	const uid = process.getuid?.();
	if (uid === undefined) return result;

	let ps: ChildProcess;
	try {
		// lstart is the stable process identity. stderr is deliberately ignored:
		// process listings must never enter task output.
		// PPID catches native descendants that do not expose inherited env in -E.
		// A native child that fully reparents before any snapshot cannot be inferred.
		ps = spawn("/bin/ps", ["-A", "-E", "-ww", "-o", "uid=,pid=,ppid=,lstart=,command="], {
			stdio: ["ignore", "pipe", "ignore"],
		});
	} catch {
		return result;
	}

	return await new Promise((resolve) => {
		const chunks: Buffer[] = [];
		let bytes = 0;
		let complete = true;
		let stopping = false;
		let settled = false;
		let timeout: NodeJS.Timeout | undefined;
		let postKillTimeout: NodeJS.Timeout | undefined;

		const finish = (scan: MarkerScan): void => {
			if (settled) return;
			settled = true;
			if (timeout) clearTimeout(timeout);
			if (postKillTimeout) clearTimeout(postKillTimeout);
			resolve(scan);
		};
		const stop = (): void => {
			if (stopping) return;
			stopping = true;
			complete = false;
			// Install the hard bound before killing in case a mocked or unusual
			// ChildProcess emits close synchronously from kill().
			postKillTimeout = setTimeout(() => finish(emptyMarkerScan()), POST_KILL_WAIT_MS);
			try { ps.kill("SIGKILL"); } catch { /* already gone */ }
			// Do not let a broken/reaped ps implementation hold shutdown forever.
		};

		ps.stdout?.on("data", (chunk: Buffer) => {
			if (stopping) return;
			bytes += chunk.byteLength;
			if (bytes <= MAX_PS_OUTPUT_BYTES) chunks.push(chunk);
			else stop();
		});
		ps.once("error", () => { complete = false; });
		ps.once("close", (code) => {
			if (code !== 0 || !complete || stopping) {
				finish(emptyMarkerScan());
				return;
			}
			result.complete = true;
			const marker = `${CONTAINMENT_ENV}=${token}`;
			const processes: MacProcess[] = [];
			for (const line of Buffer.concat(chunks).toString("utf8").split("\n")) {
				// macOS lstart is a fixed-width 24-byte field, including its spaces.
				const match = /^\s*(\d+)\s+(\d+)\s+(\d+)\s+(.{24})\s+(.*)$/.exec(line);
				if (!match) continue;
				const row = {
					uid: Number(match[1]),
					pid: Number(match[2]),
					ppid: Number(match[3]),
					identity: { pid: Number(match[2]), startSignature: match[4]!.trim() },
					command: match[5]!,
				};
				if (row.uid !== uid || !isSafePid(row.pid) || !row.identity.startSignature) continue;
				processes.push(row);
				if (row.command.split(/\s+/).includes(marker)) {
					result.pids.add(row.pid);
					result.identities.set(row.pid, row.identity);
				}
			}

			const byPid = new Map(processes.map((row) => [row.pid, row]));
			const currentRoot = rootPid === undefined ? undefined : byPid.get(rootPid)?.identity;
			const observedRoot = rootIdentity
				? (sameIdentity(currentRoot, rootIdentity) ? currentRoot : undefined)
				: allowRootSeed ? currentRoot : undefined;
			const childrenByPpid = new Map<number, MacProcess[]>();
			for (const row of processes) {
				const children = childrenByPpid.get(row.ppid) ?? [];
				children.push(row);
				childrenByPpid.set(row.ppid, children);
			}
			const seeds = new Set<number>();
			if (observedRoot) seeds.add(observedRoot.pid);
			for (const pid of previouslyDiscoveredPids) {
				const row = byPid.get(pid);
				if (!row || !sameIdentity(row.identity, previouslyDiscoveredIdentities.get(pid))) continue;
				seeds.add(pid);
				result.pids.add(pid);
				result.identities.set(pid, row.identity);
				result.discoveredPids.add(pid);
				result.discoveredIdentities.set(pid, row.identity);
			}
			const pending = [...seeds];
			for (let index = 0; index < pending.length; index++) {
				const parentPid = pending[index]!;
				for (const row of childrenByPpid.get(parentPid) ?? []) {
					if (result.discoveredPids.has(row.pid)) continue;
					result.discoveredPids.add(row.pid);
					result.discoveredIdentities.set(row.pid, row.identity);
					result.pids.add(row.pid);
					result.identities.set(row.pid, row.identity);
					pending.push(row.pid);
				}
			}
			result.rootIdentity = observedRoot;
			finish(result);
		});
		timeout = setTimeout(stop, MARKER_SCAN_TIMEOUT_MS);
	});
}

async function scanMarkerProcesses(
	token: string,
	rootPid: number | undefined,
	rootIdentity: ProcessIdentity | undefined,
	allowRootSeed: boolean,
	previouslyDiscoveredPids: Set<number>,
	previouslyDiscoveredIdentities: Map<number, ProcessIdentity>,
): Promise<MarkerScan> {
	if (process.platform === "darwin") {
		return await scanMacProcesses(
			token,
			rootPid,
			rootIdentity,
			allowRootSeed,
			previouslyDiscoveredPids,
			previouslyDiscoveredIdentities,
		);
	}
	if (process.platform !== "linux") return emptyMarkerScan();
	return await scanLinuxProcesses(token, previouslyDiscoveredPids);
}

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
	/** The shell exited cleanly, but its stdio required forced cleanup. */
	forcedCleanup: boolean;
	/** Someone already read the terminal result, so suppress auto-delivery. */
	consumed: boolean;
	/** Private inherited label used to find descendants outside our process group. */
	token: string;
	/** Same-UID descendants found on macOS, retained across rescans/reparenting. */
	discoveredPids: Set<number>;
	/** Start signatures for the retained macOS descendants. */
	discoveredIdentities: Map<number, ProcessIdentity>;
	/** Start signature for the shell root, captured while it was observed alive. */
	rootIdentity?: ProcessIdentity;
	/** Containment cleanup and settlement are shared by exit and cancellation. */
	cleanupPromise?: Promise<void>;
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
		// Reserve synchronously: two parallel command launches must not both pass.
		if (this.runningCount() + this.reserved >= MAX_RUNNING) {
			throw new Error(
				`Max ${MAX_RUNNING} background commands can run at once. Cancel one with task_cancel before starting another.`,
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
			forcedCleanup: false,
			consumed: false,
			token: randomBytes(32).toString("hex"),
			discoveredPids: new Set(),
			discoveredIdentities: new Map(),
			settleWaiters: [],
		};

		try {
			const isWindows = process.platform === "win32";
			// Agents commonly use `set -o pipefail` for CI guards. POSIX sh does
			// not provide it, so use Bash consistently across macOS and Linux.
			const shell = isWindows ? (process.env.ComSpec ?? "cmd.exe") : "bash";
			const args = isWindows ? ["/d", "/s", "/c", command] : ["-c", command];
			const child = spawn(shell, args, {
				cwd: options.cwd,
				env: { ...process.env, [CONTAINMENT_ENV]: entry.token },
				// No stdin: anything prompting sees EOF instead of hanging.
				stdio: ["ignore", "pipe", "pipe"],
				// Own process group on POSIX for fast-path termination; containment
				// scans also catch escaped or reparented normal descendants.
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
				this.requestSettle(entry);
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
						entry.forcedCleanup = true;
						entry.snapshot.errorText ??= "stdio did not close after exit; output may be incomplete";
						this.requestSettle(entry);
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
				this.requestSettle(entry);
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

	/** Decide the terminal state exactly once, after containment is verified. */
	private settleNow(entry: Entry): void {
		if (entry.snapshot.status !== "running") return;
		if (entry.exitTimer) {
			clearTimeout(entry.exitTimer);
			entry.exitTimer = undefined;
		}
		const snap = entry.snapshot;
		snap.settledAt = Date.now();
		snap.status = entry.killRequested
			? "killed"
			: entry.errored || entry.forcedCleanup
				? "failed"
				: snap.exitCode === 0 ? "done" : "failed";
		snap.stdout = entry.stdout.view();
		snap.stderr = entry.stderr.view();
		for (const waiter of entry.settleWaiters.splice(0)) waiter();
		if (!this.disposed) this.onSettleHook?.(this.snapshot(entry), entry.consumed);
	}

	/** Scan, terminate, and only then permit the entry to settle. */
	private requestSettle(entry: Entry): Promise<void> {
		if (entry.snapshot.status !== "running") return Promise.resolve();
		// A normally closed Windows process is already gone. In particular, do
		// not taskkill its PID: it may have been reused by an unrelated process.
		if (process.platform === "win32" && !entry.killRequested && !entry.forcedCleanup) {
			this.settleNow(entry);
			return Promise.resolve();
		}
		if (entry.cleanupPromise) return entry.cleanupPromise;
		entry.cleanupPromise = this.cleanupContainment(entry)
			.then((failure) => {
				if (failure) {
					entry.forcedCleanup = true;
					entry.snapshot.errorText ??= failure;
				}
			})
			.catch((error: unknown) => {
				entry.forcedCleanup = true;
				entry.snapshot.errorText ??= `process containment scan failed: ${bounded(String(error))}`;
			})
			.finally(() => this.settleNow(entry));
		return entry.cleanupPromise;
	}

	private async cleanupContainment(entry: Entry): Promise<string | undefined> {
		if (process.platform === "win32") {
			this.killTree(entry, "SIGTERM");
			return undefined;
		}
		const deadline = Date.now() + STOP_TIMEOUT_MS - POST_KILL_WAIT_MS;
		const scanProcesses = async (): Promise<MarkerScan> => {
			const scan = await scanMarkerProcesses(
				entry.token,
				entry.snapshot.pid,
				entry.rootIdentity,
				!entry.exited && entry.rootIdentity === undefined,
				entry.discoveredPids,
				entry.discoveredIdentities,
			);
			if (entry.rootIdentity === undefined && scan.rootIdentity !== undefined) {
				entry.rootIdentity = scan.rootIdentity;
			}
			for (const pid of scan.discoveredPids) entry.discoveredPids.add(pid);
			for (const [pid, identity] of scan.discoveredIdentities) {
				// Never replace a retained identity: a changed signature means this
				// PID was reused and must not become a new cleanup target.
				if (!entry.discoveredIdentities.has(pid)) entry.discoveredIdentities.set(pid, identity);
			}
			return scan;
		};
		let scan = await scanProcesses();
		this.killTree(entry, "SIGTERM", scan.pids, scan.identities, scan.rootIdentity);

		// This is the rescan before KILL. Polling lets a normally exiting shell
		// settle promptly while still giving TERM-trapping descendants a chance.
		const termDeadline = Math.min(deadline, Date.now() + FORCE_KILL_AFTER_MS);
		while ((!entry.exited || scan.pids.size > 0 || !scan.complete) && Date.now() < termDeadline) {
			await new Promise((resolve) => setTimeout(resolve, 100));
			scan = await scanProcesses();
			if (entry.exited && scan.complete && scan.pids.size === 0) break;
		}
		if (entry.exited && scan.complete && scan.pids.size === 0) {
			scan = await scanProcesses();
			if (scan.complete && scan.pids.size === 0) return undefined;
		}

		this.killTree(entry, "SIGKILL", scan.pids, scan.identities, scan.rootIdentity);
		// This is the rescan after KILL. Repeat boundedly for process-exit races.
		while (Date.now() < deadline) {
			scan = await scanProcesses();
			if (scan.complete && scan.pids.size === 0) return undefined;
			this.killTree(entry, "SIGKILL", scan.pids, scan.identities, scan.rootIdentity);
			await new Promise((resolve) => setTimeout(resolve, 100));
		}
		scan = await scanProcesses();
		return scan.complete && scan.pids.size === 0
			? undefined
			: "process containment remained non-empty or could not be completely scanned before shutdown deadline";
	}

	/** Signal only the process identity validated by the immediately preceding scan. */
	private killTree(
		entry: Entry,
		signal: NodeJS.Signals,
		markerPids = new Set<number>(),
		markerIdentities = new Map<number, ProcessIdentity>(),
		rootIdentity?: ProcessIdentity,
	): void {
		const child = entry.child;
		const pid = child?.pid;
		if (process.platform === "win32") {
			if (!child || !pid) return;
			try {
				const args = ["/pid", String(pid), "/T"];
				if (signal === "SIGKILL") args.push("/F");
				const killer = spawn("taskkill", args, { stdio: "ignore", windowsHide: true });
				killer.on("error", () => { try { child.kill(signal); } catch { /* already gone */ } });
				killer.unref();
			} catch { try { child.kill(signal); } catch { /* already gone */ } }
			return;
		}
		if (!pid || !isSafePid(pid)) return;
		// While Node still owns a live ChildProcess, its PID cannot have been reused;
		// signal the process group even when a containment scan was incomplete. Once
		// exit is observed, require the snapshot identity instead.
		const childStillOwnsPid = !entry.exited && child?.exitCode === null && child?.signalCode === null;
		const canSignalGroup = childStillOwnsPid || (
			!entry.exited && process.platform !== "darwin"
		) || (
			!entry.exited && sameIdentity(entry.rootIdentity, rootIdentity)
		);
		if (canSignalGroup) {
			try { process.kill(-pid, signal); } catch {
				if (process.platform !== "darwin") {
					try { child?.kill(signal); } catch { /* already gone */ }
				}
			}
		}
		for (const markerPid of markerPids) {
			if (!isSafePid(markerPid)) continue;
			if (process.platform === "darwin") {
				const current = markerIdentities.get(markerPid);
				const retained = entry.discoveredIdentities.get(markerPid);
				// `current` came from this scan; retained identities additionally
				// prevent a reused PID from being signalled after reparenting.
				if (!current || (retained !== undefined && !sameIdentity(retained, current))) continue;
			}
			try { process.kill(markerPid, signal); } catch { /* already gone */ }
		}
	}

	/** SIGTERM, then SIGKILL if containment does not become empty in time. */
	async kill(id: string): Promise<TerminalSnapshot> {
		const entry = this.entries.get(id);
		if (!entry) throw new Error(`No background command backend ${id}. Use task_list to see public task ids.`);
		if (entry.snapshot.status !== "running") return this.snapshot(entry);
		entry.killRequested = true;
		entry.consumed = true;
		const settled = new Promise<void>((resolve) => entry.settleWaiters.push(resolve));
		await this.requestSettle(entry);
		await settled;
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
		const running = [...this.entries.entries()]
			.filter(([, entry]) => entry.snapshot.status === "running");
		const shutdown = Promise.allSettled(running.map(([id]) => this.kill(id)));
		const completed = await Promise.race([
			shutdown.then(() => true),
			new Promise<false>((resolve) => {
				const timer = setTimeout(() => resolve(false), STOP_TIMEOUT_MS);
				timer.unref?.();
			}),
		]);
		if (!completed) {
			for (const [, entry] of running) {
				if (entry.snapshot.status !== "running") continue;
				entry.killRequested = true;
				entry.snapshot.errorText ??= "process tree remained alive at shutdown deadline";
				this.killTree(entry, "SIGKILL");
				// This is the bounded-failure escape hatch: cleanup reached the
				// shutdown deadline, so do not hold Pi open forever.
				this.settleNow(entry);
			}
		}
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
