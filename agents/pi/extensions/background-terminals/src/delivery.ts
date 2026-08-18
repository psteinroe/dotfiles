import type { TerminalSnapshot } from "./manager.ts";

type Timer = ReturnType<typeof setTimeout>;
type SendMessage = (snapshot: TerminalSnapshot) => unknown;

export interface DeliveryOptions {
  quietMs?: number;
  retryMs?: number;
}

/**
 * Delivers settled terminals only while the agent is idle.
 *
 * The manager can settle from a child-process event at any point in a turn, so
 * delivery state is kept separate from process state. Timers are owned here
 * too, which makes shutdown and retry behavior explicit instead of relying on
 * a later lifecycle event to wake a stale queue.
 */
export class BackgroundTerminalDelivery {
  private readonly pending = new Map<string, TerminalSnapshot>();
  private readonly quietMs: number;
  private readonly retryMs: number;
  private idle = true;
  private closed = false;
  private flushing = false;
  private quietTimer?: Timer;
  private retryTimer?: Timer;

  constructor(
    private readonly sendMessage: SendMessage,
    options: DeliveryOptions = {},
  ) {
    this.quietMs = options.quietMs ?? 250;
    this.retryMs = options.retryMs ?? 1_000;
  }

  setBusy(): void {
    if (this.closed) return;
    this.idle = false;
    this.clearTimers();
  }

  setIdle(): void {
    if (this.closed) return;
    this.idle = true;
    this.scheduleQuiet();
  }

  enqueue(snapshot: TerminalSnapshot): void {
    if (this.closed) return;
    this.pending.set(snapshot.id, snapshot);
    this.scheduleQuiet();
  }

  consume(id: string): void {
    this.pending.delete(id);
    if (!this.pending.size) this.clearTimers();
  }

  shutdown(): void {
    this.closed = true;
    this.pending.clear();
    this.clearTimers();
  }

  private clearTimers(): void {
    if (this.quietTimer) {
      clearTimeout(this.quietTimer);
      this.quietTimer = undefined;
    }
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = undefined;
    }
  }

  private scheduleQuiet(): void {
    if (this.closed || !this.idle || !this.pending.size || this.flushing) return;
    if (this.quietTimer || this.retryTimer) return;
    this.quietTimer = setTimeout(() => {
      this.quietTimer = undefined;
      void this.flush();
    }, this.quietMs);
    this.quietTimer.unref?.();
  }

  private scheduleRetry(): void {
    if (this.closed || !this.idle || !this.pending.size || this.retryTimer) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = undefined;
      void this.flush();
    }, this.retryMs);
    this.retryTimer.unref?.();
  }

  private async flush(): Promise<void> {
    if (this.closed || !this.idle || this.flushing || !this.pending.size) return;
    this.flushing = true;
    let failed = false;
    try {
      for (const [id, snapshot] of [...this.pending]) {
        if (this.closed || !this.idle) break;
        // Remove before sending so a successful send cannot be delivered twice.
        // A failed send is put back below for an autonomous retry.
        if (this.pending.get(id) !== snapshot) continue;
        this.pending.delete(id);
        try {
          await this.sendMessage(snapshot);
        } catch {
          failed = true;
          if (!this.closed) this.pending.set(id, snapshot);
        }
      }
    } finally {
      this.flushing = false;
      if (this.closed || !this.pending.size || !this.idle) return;
      if (failed) this.scheduleRetry();
      else this.scheduleQuiet();
    }
  }
}
