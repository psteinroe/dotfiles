import { spawn } from "node:child_process";
import path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  DEFAULT_MAX_BYTES,
  createBashTool,
  createEditTool,
  createFindTool,
  createLsTool,
  createReadTool,
  createWriteTool,
  formatSize,
  truncateHead,
  type BashOperations,
  type EditOperations,
  type FindOperations,
  type LsOperations,
  type ReadOperations,
  type WriteOperations,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

type RemoteConfig = {
  host: string;
  cwd: string;
  user: string;
  home: string;
  dotfiles: string;
  path: string;
};

type SshRunOptions = {
  input?: Buffer | string;
  signal?: AbortSignal;
  timeout?: number;
  onData?: (data: Buffer) => void;
  allowCodes?: number[];
};

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function shellJoin(values: string[]): string {
  return values.map(shellQuote).join(" ");
}

function remoteRunner(config: RemoteConfig, command: string): string {
  const encoded = Buffer.from(command).toString("base64");
  const zsh = `${config.home}/.nix-profile/bin/zsh`;
  return [
    `encoded=${shellQuote(encoded)}`,
    `cmd=$(printf %s "$encoded" | base64 -d)`,
    "sudo",
    "-u",
    shellQuote(config.user),
    `HOME=${shellQuote(config.home)}`,
    `USER=${shellQuote(config.user)}`,
    `LOGNAME=${shellQuote(config.user)}`,
    `PATH=${shellQuote(config.path)}`,
    `TERM=${shellQuote(process.env.TERM || "xterm-256color")}`,
    shellQuote(zsh),
    "-lc",
    '"$cmd"',
  ].join(" ");
}

function sshRun(config: RemoteConfig, command: string, options: SshRunOptions = {}) {
  return new Promise<{ code: number | null; stdout: Buffer; stderr: Buffer }>((resolve, reject) => {
    const child = spawn("ssh", ["-T", config.host, remoteRunner(config, command)], {
      stdio: [options.input === undefined ? "ignore" : "pipe", "pipe", "pipe"],
    });
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    let timedOut = false;
    const allowCodes = options.allowCodes ?? [0];

    const timer = options.timeout
      ? setTimeout(() => {
          timedOut = true;
          child.kill();
        }, options.timeout * 1000)
      : undefined;

    const onAbort = () => child.kill();
    options.signal?.addEventListener("abort", onAbort, { once: true });

    child.stdout.on("data", (data: Buffer) => {
      stdout.push(data);
      options.onData?.(data);
    });
    child.stderr.on("data", (data: Buffer) => {
      stderr.push(data);
      options.onData?.(data);
    });
    child.on("error", (error) => {
      if (timer) clearTimeout(timer);
      options.signal?.removeEventListener("abort", onAbort);
      reject(error);
    });
    child.on("close", (code) => {
      if (timer) clearTimeout(timer);
      options.signal?.removeEventListener("abort", onAbort);

      const out = Buffer.concat(stdout);
      const err = Buffer.concat(stderr);
      if (options.signal?.aborted) {
        reject(new Error("aborted"));
        return;
      }
      if (timedOut) {
        reject(new Error(`timeout:${options.timeout}`));
        return;
      }
      if (!allowCodes.includes(code ?? -1)) {
        reject(new Error(`SSH failed (${code}): ${err.toString()}`));
        return;
      }
      resolve({ code, stdout: out, stderr: err });
    });

    if (options.input !== undefined && child.stdin) {
      child.stdin.end(options.input);
    }
  });
}

function remoteSetup(config: RemoteConfig): string {
  return `export PATH=${shellQuote(config.path)}; fpath=(${shellQuote(`${config.dotfiles}/zsh/functions`)} $fpath); autoload -Uz gpr gh gh-default-branch wtsetup wtcheckout wtensure`;
}

function toRemotePath(localCwd: string, remoteCwd: string, inputPath: string): string {
  const absolute = path.resolve(inputPath);
  if (absolute === localCwd) return remoteCwd;
  const prefix = `${localCwd}${path.sep}`;
  if (!absolute.startsWith(prefix)) return absolute;
  const relative = absolute.slice(prefix.length).split(path.sep).join("/");
  return `${remoteCwd}/${relative}`;
}

function toLocalPath(localSearchPath: string, remoteSearchPath: string, remotePath: string): string {
  const normalized = remotePath.replace(/\/+$|\r/g, "");
  if (normalized.startsWith(`${remoteSearchPath}/`)) {
    return path.join(localSearchPath, normalized.slice(remoteSearchPath.length + 1));
  }
  return path.join(localSearchPath, normalized.replace(/^\.\//, ""));
}

function createRemoteReadOps(config: RemoteConfig, localCwd: string): ReadOperations {
  return {
    readFile: async (p) => (await sshRun(config, `cat -- ${shellQuote(toRemotePath(localCwd, config.cwd, p))}`)).stdout,
    access: async (p) => {
      await sshRun(config, `test -r ${shellQuote(toRemotePath(localCwd, config.cwd, p))}`);
    },
    detectImageMimeType: async (p) => {
      try {
        const result = await sshRun(config, `file --mime-type -b -- ${shellQuote(toRemotePath(localCwd, config.cwd, p))}`);
        const mime = result.stdout.toString().trim();
        return ["image/jpeg", "image/png", "image/gif", "image/webp"].includes(mime) ? mime : null;
      } catch {
        return null;
      }
    },
  };
}

function createRemoteWriteOps(config: RemoteConfig, localCwd: string): WriteOperations {
  return {
    writeFile: async (p, content) => {
      const remotePath = toRemotePath(localCwd, config.cwd, p);
      const command = `mkdir -p -- ${shellQuote(path.posix.dirname(remotePath))} && cat > ${shellQuote(remotePath)}`;
      await sshRun(config, command, { input: Buffer.from(content) });
    },
    mkdir: async (dir) => {
      await sshRun(config, `mkdir -p -- ${shellQuote(toRemotePath(localCwd, config.cwd, dir))}`);
    },
  };
}

function createRemoteEditOps(config: RemoteConfig, localCwd: string): EditOperations {
  const read = createRemoteReadOps(config, localCwd);
  const write = createRemoteWriteOps(config, localCwd);
  return { readFile: read.readFile, access: read.access, writeFile: write.writeFile };
}

function createRemoteBashOps(config: RemoteConfig, localCwd: string): BashOperations {
  return {
    exec: async (command, cwd, { onData, signal, timeout }) => {
      const remoteCwd = toRemotePath(localCwd, config.cwd, cwd);
      const wrapped = `${remoteSetup(config)}; cd ${shellQuote(remoteCwd)} && ${command}`;
      const result = await sshRun(config, wrapped, { onData, signal, timeout, allowCodes: Array.from({ length: 256 }, (_, i) => i) });
      return { exitCode: result.code };
    },
  };
}

function createRemoteLsOps(config: RemoteConfig, localCwd: string): LsOperations {
  const dirCache = new Map<string, boolean>();
  return {
    exists: async (p) => {
      const result = await sshRun(config, `test -e ${shellQuote(toRemotePath(localCwd, config.cwd, p))}`, { allowCodes: [0, 1] });
      return result.code === 0;
    },
    stat: async (p) => {
      const remotePath = toRemotePath(localCwd, config.cwd, p);
      let isDir = dirCache.get(remotePath);
      if (isDir === undefined) {
        const result = await sshRun(config, `test -d ${shellQuote(remotePath)}`, { allowCodes: [0, 1] });
        isDir = result.code === 0;
      }
      return { isDirectory: () => isDir };
    },
    readdir: async (p) => {
      const remoteDir = toRemotePath(localCwd, config.cwd, p);
      const result = await sshRun(config, `find ${shellQuote(remoteDir)} -mindepth 1 -maxdepth 1 -printf '%f\t%y\n'`);
      const entries: string[] = [];
      for (const line of result.stdout.toString().split("\n")) {
        if (!line) continue;
        const tab = line.lastIndexOf("\t");
        const name = tab >= 0 ? line.slice(0, tab) : line;
        const type = tab >= 0 ? line.slice(tab + 1) : "";
        entries.push(name);
        dirCache.set(`${remoteDir}/${name}`, type === "d");
      }
      return entries;
    },
  };
}

function createRemoteFindOps(config: RemoteConfig, localCwd: string): FindOperations {
  return {
    exists: async (p) => {
      const result = await sshRun(config, `test -e ${shellQuote(toRemotePath(localCwd, config.cwd, p))}`, { allowCodes: [0, 1] });
      return result.code === 0;
    },
    glob: async (pattern, cwd, { limit }) => {
      const remoteSearchPath = toRemotePath(localCwd, config.cwd, cwd);
      const args = [
        "fd",
        "--glob",
        "--color=never",
        "--hidden",
        "--no-require-git",
        "--max-results",
        String(limit),
        "--exclude",
        ".git",
        "--exclude",
        "node_modules",
        "--",
        pattern,
        ".",
      ];
      const result = await sshRun(config, `cd ${shellQuote(remoteSearchPath)} && ${shellJoin(args)}`, { allowCodes: [0, 1] });
      return result.stdout
        .toString()
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean)
        .map((line) => toLocalPath(cwd, remoteSearchPath, line));
    },
  };
}

const grepSchema = Type.Object({
  pattern: Type.String({ description: "Search pattern (regex or literal string)" }),
  path: Type.Optional(Type.String({ description: "Directory or file to search (default: current directory)" })),
  glob: Type.Optional(Type.String({ description: "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'" })),
  ignoreCase: Type.Optional(Type.Boolean({ description: "Case-insensitive search (default: false)" })),
  literal: Type.Optional(Type.Boolean({ description: "Treat pattern as literal string instead of regex (default: false)" })),
  context: Type.Optional(Type.Number({ description: "Number of lines to show before and after each match (default: 0)" })),
  limit: Type.Optional(Type.Number({ description: "Maximum number of matches to return (default: 100)" })),
});

function createRemoteGrepTool(config: RemoteConfig, localCwd: string) {
  return {
    name: "grep",
    label: "grep",
    description: `Search remote file contents for a pattern. Returns matching lines with file paths and line numbers. Respects .gitignore. Output is truncated to 100 matches or ${DEFAULT_MAX_BYTES / 1024}KB (whichever is hit first).`,
    promptSnippet: "Search remote file contents for patterns (respects .gitignore)",
    parameters: grepSchema,
    async execute(_toolCallId: string, params: any, signal?: AbortSignal) {
      const searchPath = path.resolve(localCwd, params.path || ".");
      const remoteSearchPath = toRemotePath(localCwd, config.cwd, searchPath);
      const isDir = (await sshRun(config, `test -d ${shellQuote(remoteSearchPath)}`, { allowCodes: [0, 1], signal })).code === 0;
      const effectiveLimit = Math.max(1, params.limit ?? 100);
      const contextLines = params.context && params.context > 0 ? Math.floor(params.context) : 0;
      const rgArgs = ["rg", "--line-number", "--color=never", "--hidden"];
      if (params.ignoreCase) rgArgs.push("--ignore-case");
      if (params.literal) rgArgs.push("--fixed-strings");
      if (contextLines > 0) rgArgs.push("--context", String(contextLines));
      if (params.glob) rgArgs.push("--glob", params.glob);
      rgArgs.push("--", params.pattern, isDir ? "." : path.posix.basename(remoteSearchPath));
      const workDir = isDir ? remoteSearchPath : path.posix.dirname(remoteSearchPath);
      const result = await sshRun(config, `cd ${shellQuote(workDir)} && ${shellJoin(rgArgs)}`, { allowCodes: [0, 1], signal });
      const rawLines = result.stdout.toString().replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n").filter(Boolean);
      if (rawLines.length === 0) {
        return { content: [{ type: "text", text: "No matches found" }], details: undefined };
      }
      const maxLines = effectiveLimit * Math.max(1, contextLines * 2 + 2);
      const limited = rawLines.slice(0, maxLines).map((line) => line.replace(/^\.\//, ""));
      let output = limited.join("\n");
      const truncation = truncateHead(output, { maxLines: Number.MAX_SAFE_INTEGER });
      output = truncation.content;
      const details: Record<string, unknown> = {};
      const notices: string[] = [];
      if (rawLines.length > limited.length) {
        notices.push(`${effectiveLimit} matches/context limit reached`);
        details.matchLimitReached = effectiveLimit;
      }
      if (truncation.truncated) {
        notices.push(`${formatSize(DEFAULT_MAX_BYTES)} limit reached`);
        details.truncation = truncation;
      }
      if (notices.length > 0) output += `\n\n[${notices.join(". ")}]`;
      return { content: [{ type: "text", text: output }], details: Object.keys(details).length ? details : undefined };
    },
  };
}

export default function (pi: ExtensionAPI) {
  pi.registerFlag("remote-ssh", { description: "Run coding tools on this SSH host", type: "string" });
  pi.registerFlag("remote-cwd", { description: "Remote working directory for SSH-delegated tools", type: "string" });
  pi.registerFlag("remote-user", { description: "Remote sudo target user", type: "string", default: "psteinroe" });
  pi.registerFlag("remote-home", { description: "Remote target user home", type: "string" });
  pi.registerFlag("remote-dotfiles", { description: "Remote dotfiles path", type: "string" });

  const localCwd = process.cwd();
  let config: RemoteConfig | null = null;
  let registered = false;

  pi.on("session_start", async (_event, ctx) => {
    const host = pi.getFlag("remote-ssh") as string | undefined;
    const cwd = pi.getFlag("remote-cwd") as string | undefined;
    if (!host && !cwd) return;
    if (!host || !cwd) {
      ctx.ui.notify("Both --remote-ssh and --remote-cwd are required for remote Pi mode", "error");
      return;
    }

    const user = (pi.getFlag("remote-user") as string | undefined) || "psteinroe";
    const home = (pi.getFlag("remote-home") as string | undefined) || `/home/${user}`;
    const dotfiles = (pi.getFlag("remote-dotfiles") as string | undefined) || `${home}/Developer/dotfiles`;
    config = {
      host,
      cwd,
      user,
      home,
      dotfiles,
      path: `${home}/.local/bin:${home}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`,
    };

    if (!registered) {
      registered = true;
      pi.registerTool({ ...createReadTool(localCwd, { operations: createRemoteReadOps(config, localCwd) }) });
      pi.registerTool({ ...createWriteTool(localCwd, { operations: createRemoteWriteOps(config, localCwd) }) });
      pi.registerTool({ ...createEditTool(localCwd, { operations: createRemoteEditOps(config, localCwd) }) });
      pi.registerTool({ ...createBashTool(localCwd, { operations: createRemoteBashOps(config, localCwd) }) });
      pi.registerTool({ ...createLsTool(localCwd, { operations: createRemoteLsOps(config, localCwd) }) });
      pi.registerTool({ ...createFindTool(localCwd, { operations: createRemoteFindOps(config, localCwd) }) });
      pi.registerTool(createRemoteGrepTool(config, localCwd) as any);
    }

    ctx.ui.setStatus("remote-ssh", ctx.ui.theme.fg("accent", `SSH: ${host}:${cwd}`));
    ctx.ui.notify(`Remote Pi tools: ${host}:${cwd}`, "info");
  });

  pi.on("user_bash", () => {
    if (!config) return;
    return { operations: createRemoteBashOps(config, localCwd) };
  });

  pi.on("before_agent_start", async (event) => {
    if (!config) return;
    return {
      systemPrompt: event.systemPrompt.replace(
        `Current working directory: ${localCwd}`,
        `Current working directory: ${config.cwd} (remote via SSH: ${config.host}; local shadow cwd: ${localCwd})`,
      ),
    };
  });
}
