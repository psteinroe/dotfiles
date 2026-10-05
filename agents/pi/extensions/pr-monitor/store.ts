import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";
import type { PollState } from "./state.ts";

interface Owner { pid: number; token: string }
function alive(pid: number): boolean {
  if (!Number.isSafeInteger(pid) || pid <= 0) return true; // uncertain ownership is never stolen
  try { process.kill(pid, 0); return true; } catch (error: any) { return error.code !== "ESRCH"; }
}

/** Per-user, per-host store. Locks are stolen only from a confirmed dead PID, never on an age/heartbeat guess. */
export class SharedStore {
  readonly directory: string;
  constructor(directory: string) { this.directory = directory; fs.mkdirSync(directory, { recursive: true, mode: 0o700 }); }
  private file(key: string, suffix: string): string {
    if (!/^[a-f0-9]{64}$/.test(key)) throw new Error("Invalid PR monitor key.");
    return path.join(this.directory, `${key}.${suffix}`);
  }
  read(key: string): PollState | undefined {
    try {
      const state = JSON.parse(fs.readFileSync(this.file(key, "json"), "utf8"));
      if (state.target?.key === key && Number.isFinite(state.observedAt) && Number.isFinite(state.nextPollAt)
        && typeof state.status === "string" && Array.isArray(state.checks)) return state;
    } catch { /* A missing or corrupt cache is not a successful poll. */ }
  }
  write(key: string, state: PollState): void {
    const file = this.file(key, "json");
    const temp = `${file}.${randomUUID()}.tmp`;
    try { fs.writeFileSync(temp, JSON.stringify(state), { mode: 0o600 }); fs.renameSync(temp, file); }
    finally { fs.rmSync(temp, { force: true }); }
  }
  private owner(lock: string): Owner | undefined {
    try { return JSON.parse(fs.readFileSync(path.join(lock, "owner.json"), "utf8")); } catch { return; }
  }
  acquire(key: string): (() => void) | undefined { return this.claimDirectory(this.file(key, "lock")); }
  private claimDirectory(lock: string, depth = 0): (() => void) | undefined {
    if (depth > 8) return; // refuse uncertain/corrupt lock trees
    // Publish a nonempty, fully initialized directory atomically. There is no window with a lock but no owner.
    const token = randomUUID();
    const stage = `${lock}.${token}.tmp`;
    try { fs.mkdirSync(stage, { mode: 0o700 }); }
    catch (error: any) { if (error.code === "ENOENT") return; throw error; }
    try { fs.writeFileSync(path.join(stage, "owner.json"), JSON.stringify({ pid: process.pid, token }), { mode: 0o600 }); }
    catch (error: any) {
      fs.rmSync(stage, { recursive: true, force: true });
      if (error.code === "ENOENT") return;
      throw error;
    }
    const claim = () => {
      try { fs.renameSync(stage, lock); return true; }
      catch (error: any) { if (["EEXIST", "ENOTEMPTY", "ENOENT"].includes(error.code)) return false; throw error; }
    };
    try {
      if (!claim()) {
        const owner = this.owner(lock);
        if (!owner || alive(owner.pid)) return;
        // Serialize stale-lock reclamation. Re-read after acquiring this barrier: another contender may have replaced the lock.
        const releaseReaper = this.claimDirectory(path.join(lock, "reap"), depth + 1);
        if (!releaseReaper) return;
        try {
          const current = this.owner(lock);
          if (!current || alive(current.pid)) return;
          fs.rmSync(lock, { recursive: true });
          if (!claim()) return;
        } finally { releaseReaper(); }
      }
      return () => {
        if (this.owner(lock)?.token === token) fs.rmSync(lock, { recursive: true, force: true });
      };
    } finally { fs.rmSync(stage, { recursive: true, force: true }); }
  }
}
