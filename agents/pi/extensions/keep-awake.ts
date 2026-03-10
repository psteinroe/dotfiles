import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";

const PID_DIR = "/tmp/pi-caffeinate";

function getSessionKey(ctx: ExtensionContext): string {
  const sessionFile = ctx.sessionManager.getSessionFile();
  const rawKey = sessionFile ?? `ephemeral:${process.pid}`;
  return createHash("sha1").update(rawKey).digest("hex");
}

function getPidFilePath(ctx: ExtensionContext): string {
  return path.join(PID_DIR, `${getSessionKey(ctx)}.pid`);
}

function readPid(pidFile: string): number | undefined {
  try {
    const pid = Number.parseInt(readFileSync(pidFile, "utf8").trim(), 10);
    if (Number.isNaN(pid) || pid <= 0) {
      return undefined;
    }
    return pid;
  } catch {
    return undefined;
  }
}

function stopCaffeinate(ctx: ExtensionContext) {
  if (process.platform !== "darwin") {
    return;
  }

  const pidFile = getPidFilePath(ctx);
  const pid = readPid(pidFile);

  if (pid) {
    try {
      process.kill(pid);
    } catch {
      // Ignore stale pid or missing process.
    }
  }

  try {
    unlinkSync(pidFile);
  } catch {
    // Ignore missing file.
  }
}

function startCaffeinate(ctx: ExtensionContext) {
  if (process.platform !== "darwin") {
    return;
  }

  mkdirSync(PID_DIR, { recursive: true });
  stopCaffeinate(ctx);

  try {
    const child = spawn("caffeinate", ["-di"], {
      stdio: "ignore",
      detached: true,
    });
    child.unref();
    writeFileSync(getPidFilePath(ctx), String(child.pid));
  } catch {
    // Ignore missing caffeinate binary/spawn failures.
  }
}

export default function keepAwakeExtension(pi: ExtensionAPI) {
  pi.on("agent_start", async (_event, ctx) => {
    startCaffeinate(ctx);
  });

  pi.on("agent_end", async (_event, ctx) => {
    stopCaffeinate(ctx);
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    stopCaffeinate(ctx);
  });
}
