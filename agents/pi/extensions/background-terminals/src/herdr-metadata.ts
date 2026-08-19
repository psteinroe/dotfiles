import net from "node:net";

const SOURCE = "pi:background-terminals";
const PI_SOURCE = "herdr:pi";
const MAX_TTL_MS = 86_400_000;
const RENEW_AFTER_MS = 12 * 60 * 60 * 1_000;

type MetadataReport = {
	id: string;
	method: "pane.report_metadata";
	params: {
		pane_id: string;
		source: string;
		agent: "pi";
		applies_to_source: string;
		state_labels?: Record<string, string>;
		clear_state_labels?: boolean;
		seq: number;
		ttl_ms?: number;
	};
};

type HerdrConnection = {
	enabled: boolean;
	endpoint?: string;
	paneId?: string;
};

function connectionFromEnvironment(): HerdrConnection {
	const socketPath = process.env.HERDR_SOCKET_PATH;
	const paneId = process.env.HERDR_PANE_ID;
	return {
		enabled: process.env.HERDR_ENV === "1" && Boolean(socketPath && paneId),
		endpoint:
			process.platform === "win32" && socketPath ? `\\\\.\\pipe\\${socketPath}` : socketPath,
		paneId,
	};
}

function sendAttempt(endpoint: string, request: MetadataReport, timeoutMs: number): Promise<boolean> {
	return new Promise((resolve) => {
		let finished = false;
		let response = "";
		let timeout: ReturnType<typeof setTimeout> | undefined;
		let socket: net.Socket;
		const finish = (delivered: boolean) => {
			if (finished) return;
			finished = true;
			if (timeout) clearTimeout(timeout);
			socket?.destroy();
			resolve(delivered);
		};

		try {
			socket = net.createConnection(endpoint);
		} catch {
			resolve(false);
			return;
		}
		socket.setEncoding("utf8");
		socket.on("error", () => finish(false));
		socket.on("connect", () => {
			try {
				socket.write(`${JSON.stringify(request)}\n`);
			} catch {
				finish(false);
			}
		});
		socket.on("data", (chunk: string) => {
			response += chunk;
			const newline = response.indexOf("\n");
			if (newline === -1) return;
			try {
				const parsed = JSON.parse(response.slice(0, newline));
				finish(parsed?.id === request.id && parsed?.result !== undefined && parsed?.error === undefined);
			} catch {
				finish(false);
			}
		});
		socket.on("end", () => finish(false));
		timeout = setTimeout(() => finish(false), timeoutMs);
		timeout.unref?.();
	});
}

async function send(endpoint: string, request: MetadataReport): Promise<boolean> {
	try {
		if (await sendAttempt(endpoint, request, 500)) return true;
		return await sendAttempt(endpoint, request, 1_500);
	} catch {
		return false;
	}
}

export class HerdrBackgroundMetadata {
	private readonly connection = connectionFromEnvironment();
	private desired: boolean | undefined;
	private reported: boolean | undefined;
	private sequence = Date.now() * 1_000;
	private draining = false;
	private closed = false;
	private pending = Promise.resolve();
	private renewalTimer: ReturnType<typeof setTimeout> | undefined;

	setActive(active: boolean): Promise<void> {
		if (!this.connection.enabled || (this.closed && active)) return this.pending;
		this.desired = active;
		if (!active) this.stopRenewal();
		if (!this.draining && this.reported !== this.desired) {
			this.pending = this.drain();
		}
		return this.pending;
	}

	shutdown(): Promise<void> {
		this.closed = true;
		this.stopRenewal();
		return this.setActive(false);
	}

	private async drain(): Promise<void> {
		this.draining = true;
		try {
			while (this.reported !== this.desired) {
				const target = this.desired!;
				const delivered = await send(this.connection.endpoint!, this.report(target));
				if (!delivered) {
					// If the desired state changed while this report was in flight,
					// still attempt the newer transition (especially shutdown clears).
					if (target !== this.desired) continue;
					return;
				}
				this.reported = target;
				if (target) this.scheduleRenewal();
			}
		} finally {
			this.draining = false;
		}
	}

	private scheduleRenewal(): void {
		this.stopRenewal();
		if (this.closed || this.desired !== true) return;
		this.renewalTimer = setTimeout(() => {
			this.renewalTimer = undefined;
			if (this.closed || this.desired !== true) return;
			this.reported = undefined;
			if (!this.draining) this.pending = this.drain();
		}, RENEW_AFTER_MS);
		this.renewalTimer.unref?.();
	}

	private stopRenewal(): void {
		if (!this.renewalTimer) return;
		clearTimeout(this.renewalTimer);
		this.renewalTimer = undefined;
	}

	private report(active: boolean): MetadataReport {
		this.sequence += 1;
		return {
			id: `${SOURCE}:${Date.now()}:${Math.random().toString(36).slice(2)}`,
			method: "pane.report_metadata",
			params: {
				pane_id: this.connection.paneId!,
				source: SOURCE,
				agent: "pi",
				applies_to_source: PI_SOURCE,
				...(active
					? {
							state_labels: { idle: "background", done: "background" },
							ttl_ms: MAX_TTL_MS,
						}
					: { clear_state_labels: true }),
				seq: this.sequence,
			},
		};
	}
}
