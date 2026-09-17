import type { TaskSnapshot } from "./registry.ts";

type Timer = ReturnType<typeof setTimeout>;
type SendMessage = (snapshots: TaskSnapshot[]) => unknown;

export interface TaskDeliveryOptions {
  quietMs?: number;
  retryMs?: number;
  canDeliver?: () => boolean;
}

/** Idle-aware, deduplicated and batched completion delivery. */
export class TaskDelivery {
  private readonly pending = new Map<string, TaskSnapshot>();
  private readonly inFlight = new Set<string>();
  private readonly consumed = new Set<string>();
  private readonly quietMs: number;
  private readonly retryMs: number;
  private readonly canDeliver: () => boolean;
  private readonly sendMessage: SendMessage;
  private idle = true;
  private closed = false;
  private flushing = false;
  private quietTimer?: Timer;
  private retryTimer?: Timer;

  constructor(sendMessage: SendMessage, options: TaskDeliveryOptions = {}) {
    this.sendMessage = sendMessage;
    this.quietMs = options.quietMs ?? 250;
    this.retryMs = options.retryMs ?? 1_000;
    this.canDeliver = options.canDeliver ?? (() => this.idle);
  }

  setBusy(): void {
    if (this.closed) return;
    this.idle = false;
    this.clearTimers();
    this.scheduleRetry();
  }

  setIdle(): void {
    if (this.closed) return;
    this.idle = true;
    this.clearTimers();
    this.scheduleQuiet();
  }

  enqueue(snapshot: TaskSnapshot): void {
    if (this.closed || this.consumed.has(snapshot.id)) return;
    this.pending.set(snapshot.id, snapshot);
    if (this.idle) this.scheduleQuiet();
    else this.scheduleRetry();
  }

  consume(id: string): void {
    this.pending.delete(id);
    if (this.inFlight.has(id)) this.consumed.add(id);
    if (!this.pending.size) this.clearTimers();
  }

  shutdown(): void {
    this.closed = true;
    this.pending.clear();
    this.inFlight.clear();
    this.consumed.clear();
    this.clearTimers();
  }

  private clearTimers(): void {
    if (this.quietTimer) clearTimeout(this.quietTimer);
    if (this.retryTimer) clearTimeout(this.retryTimer);
    this.quietTimer = undefined;
    this.retryTimer = undefined;
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
    if (this.closed || !this.pending.size || this.flushing || this.retryTimer) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = undefined;
      void this.flush();
    }, this.retryMs);
    this.retryTimer.unref?.();
  }

  private async flush(): Promise<void> {
    if (this.closed || this.flushing || !this.pending.size) return;
    if (!this.canDeliver()) {
      this.scheduleRetry();
      return;
    }
    this.flushing = true;
    let failed = false;
    const batch = [...this.pending.values()];
    for (const task of batch) {
      if (this.pending.get(task.id) !== task) continue;
      this.pending.delete(task.id);
      this.inFlight.add(task.id);
    }
    const deliverable = batch.filter((task) =>
      this.inFlight.has(task.id) && !this.consumed.has(task.id));
    try {
      if (deliverable.length && !this.closed) {
        if (!this.canDeliver()) {
          failed = true;
          for (const task of deliverable) {
            if (!this.consumed.has(task.id)) this.pending.set(task.id, task);
          }
        } else {
          await this.sendMessage(deliverable);
        }
      }
    } catch {
      failed = true;
      if (!this.closed) {
        for (const task of deliverable) {
          if (!this.consumed.has(task.id)) this.pending.set(task.id, task);
        }
      }
    } finally {
      for (const task of batch) {
        this.inFlight.delete(task.id);
        this.consumed.delete(task.id);
      }
      this.flushing = false;
      if (this.closed || !this.pending.size) return;
      if (failed || !this.idle || !this.canDeliver()) this.scheduleRetry();
      else this.scheduleQuiet();
    }
  }
}
