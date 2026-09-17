import * as path from "node:path";
import { canonicalizePath, pathWithinScopes } from "../shared/write-scope-paths.ts";

const MAX_TRACKED_TASKS = 64;

export type TaskKind = "subagent" | "command";
export type TaskStatus = "starting" | "running" | "cancelling" | "done" | "failed" | "cancelled";

export interface TaskSnapshot {
  id: string;
  kind: TaskKind;
  title: string;
  cwd: string;
  status: TaskStatus;
  createdAt: number;
  settledAt?: number;
  agent?: "finder" | "librarian" | "oracle" | "worker";
  command?: string;
  writeScope?: string[];
  resultText?: string;
  errorText?: string;
  details?: unknown;
  backendId?: string;
}

interface TaskEntry {
  snapshot: TaskSnapshot;
  consumed: boolean;
  cancel?: () => void | Promise<void>;
}

export interface CreateTaskOptions extends Omit<TaskSnapshot, "id" | "createdAt" | "status"> {
  status?: Extract<TaskStatus, "starting" | "running">;
  cancel?: () => void | Promise<void>;
}

const isSettled = (status: TaskStatus) =>
  status === "done" || status === "failed" || status === "cancelled";

function pathsOverlap(left: string, right: string): boolean {
  return left === right || left.startsWith(`${right}${path.sep}`) || right.startsWith(`${left}${path.sep}`);
}

export class TaskRegistry {
  private readonly entries = new Map<string, TaskEntry>();
  private counter = 0;
  private closed = false;
  private settleListener?: (snapshot: TaskSnapshot, consumed: boolean) => void;

  onSettle(listener: (snapshot: TaskSnapshot, consumed: boolean) => void): void {
    this.settleListener = listener;
  }

  create(options: CreateTaskOptions): TaskSnapshot {
    if (this.closed) throw new Error("Background tasks are shutting down");
    const id = `task-${++this.counter}`;
    const snapshot: TaskSnapshot = {
      id,
      kind: options.kind,
      title: options.title,
      cwd: options.cwd,
      status: options.status ?? "starting",
      createdAt: Date.now(),
      ...(options.agent ? { agent: options.agent } : {}),
      ...(options.command ? { command: options.command } : {}),
      ...(options.writeScope ? { writeScope: [...options.writeScope] } : {}),
      ...(options.resultText ? { resultText: options.resultText } : {}),
      ...(options.errorText ? { errorText: options.errorText } : {}),
      ...(options.details !== undefined ? { details: options.details } : {}),
      ...(options.backendId ? { backendId: options.backendId } : {}),
    };
    this.entries.set(id, { snapshot, consumed: false, cancel: options.cancel });
    this.prune();
    return this.copy(snapshot);
  }

  update(id: string, patch: Partial<Omit<TaskSnapshot, "id" | "kind" | "createdAt">>): TaskSnapshot {
    const entry = this.require(id);
    if (isSettled(entry.snapshot.status)) return this.copy(entry.snapshot);
    const nextPatch = entry.snapshot.status === "cancelling" && patch.status === "running"
      ? { ...patch, status: "cancelling" as const }
      : patch;
    Object.assign(entry.snapshot, nextPatch);
    return this.copy(entry.snapshot);
  }

  settle(
    id: string,
    status: Extract<TaskStatus, "done" | "failed" | "cancelled">,
    patch: Partial<Omit<TaskSnapshot, "id" | "kind" | "createdAt" | "status" | "settledAt">> = {},
  ): TaskSnapshot {
    const entry = this.require(id);
    if (isSettled(entry.snapshot.status)) return this.copy(entry.snapshot);
    Object.assign(entry.snapshot, patch, { status, settledAt: Date.now() });
    const snapshot = this.copy(entry.snapshot);
    if (!this.closed) this.settleListener?.(snapshot, entry.consumed);
    this.prune();
    return snapshot;
  }

  get(id: string): TaskSnapshot | undefined {
    const entry = this.entries.get(id);
    return entry ? this.copy(entry.snapshot) : undefined;
  }

  list(): TaskSnapshot[] {
    return [...this.entries.values()].map((entry) => this.copy(entry.snapshot));
  }

  consume(id: string): void {
    const entry = this.entries.get(id);
    if (entry) entry.consumed = true;
    this.prune();
  }

  cancel(id: string): TaskSnapshot {
    const entry = this.require(id);
    if (isSettled(entry.snapshot.status)) return this.copy(entry.snapshot);
    entry.snapshot.status = "cancelling";
    try {
      void Promise.resolve(entry.cancel?.()).catch((error) => {
        if (!isSettled(entry.snapshot.status)) {
          this.settle(id, "failed", {
            errorText: error instanceof Error ? error.message : String(error),
          });
        }
      });
    } catch (error) {
      this.settle(id, "failed", {
        errorText: error instanceof Error ? error.message : String(error),
      });
    }
    return this.copy(entry.snapshot);
  }

  assertWriteScopeAvailable(cwd: string, scope: string[]): string[] {
    const root = canonicalizePath(cwd);
    const normalized = [...new Set(scope.map((candidate) => canonicalizePath(candidate, cwd)))];
    if (normalized.length === 0) throw new Error("Worker write_scope must not be empty.");
    for (const candidate of normalized) {
      if (candidate === root) {
        throw new Error("Worker write_scope cannot claim the entire repository.");
      }
      if (!pathWithinScopes(candidate, [root])) {
        throw new Error(`Worker write_scope must stay inside the repository: ${candidate}`);
      }
    }
    for (const entry of this.entries.values()) {
      if (entry.snapshot.agent !== "worker" || isSettled(entry.snapshot.status)) continue;
      for (const current of entry.snapshot.writeScope ?? []) {
        const currentPath = path.resolve(entry.snapshot.cwd, current);
        const overlap = normalized.find((candidate) => pathsOverlap(candidate, currentPath));
        if (overlap) {
          throw new Error(
            `Worker write scope overlaps ${entry.snapshot.id}: ${overlap} conflicts with ${currentPath}.`,
          );
        }
      }
    }
    return normalized;
  }

  conflictsWithActiveWorker(filePath: string): TaskSnapshot | undefined {
    const absolute = canonicalizePath(filePath);
    for (const entry of this.entries.values()) {
      if (entry.snapshot.agent !== "worker" || isSettled(entry.snapshot.status)) continue;
      if ((entry.snapshot.writeScope ?? []).some((candidate) =>
        pathsOverlap(absolute, canonicalizePath(candidate, entry.snapshot.cwd)))) {
        return this.copy(entry.snapshot);
      }
    }
    return undefined;
  }

  firstActiveWorker(): TaskSnapshot | undefined {
    for (const entry of this.entries.values()) {
      if (entry.snapshot.agent === "worker" && !isSettled(entry.snapshot.status)) {
        return this.copy(entry.snapshot);
      }
    }
    return undefined;
  }

  async shutdown(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    const cancellations: Promise<unknown>[] = [];
    for (const entry of this.entries.values()) {
      if (isSettled(entry.snapshot.status)) continue;
      entry.snapshot.status = "cancelling";
      try {
        cancellations.push(Promise.resolve(entry.cancel?.()));
      } catch {
        // Continue cancelling the remaining tasks.
      }
    }
    await Promise.allSettled(cancellations);
  }

  private prune(): void {
    if (this.entries.size <= MAX_TRACKED_TASKS) return;
    for (const [id, entry] of this.entries) {
      if (this.entries.size <= MAX_TRACKED_TASKS) break;
      if (entry.consumed && isSettled(entry.snapshot.status)) this.entries.delete(id);
    }
  }

  private require(id: string): TaskEntry {
    const entry = this.entries.get(id);
    if (!entry) {
      const known = [...this.entries.keys()];
      throw new Error(`No task ${id}.${known.length ? ` Known: ${known.join(", ")}` : ""}`);
    }
    return entry;
  }

  private copy(snapshot: TaskSnapshot): TaskSnapshot {
    return {
      ...snapshot,
      ...(snapshot.writeScope ? { writeScope: [...snapshot.writeScope] } : {}),
    };
  }
}
