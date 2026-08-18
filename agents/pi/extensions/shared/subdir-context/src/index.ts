import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type TextContent = { type: "text"; text: string };

const AGENTS_FILENAMES = ["AGENTS.override.md", "AGENTS.md", "CLAUDE.md"];

export default function autoloadSubdirContext(pi: ExtensionAPI) {
	const loadedAgents = new Set<string>();
	let currentCwd = "";
	let cwdAgentsPath = "";
	let homeDir = "";

	function resolvePath(targetPath: string, baseDir: string) {
		const absolute = path.isAbsolute(targetPath)
			? path.normalize(targetPath)
			: path.resolve(baseDir, targetPath);
		try {
			return fs.realpathSync.native?.(absolute) ?? fs.realpathSync(absolute);
		} catch {
			return absolute;
		}
	}

	function isInsideRoot(rootDir: string, targetPath: string) {
		if (!rootDir) return false;
		const relative = path.relative(rootDir, targetPath);
		return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
	}

	function getAgentsFileFromDir(dir: string) {
		for (const filename of AGENTS_FILENAMES) {
			const candidate = path.join(dir, filename);
			if (fs.existsSync(candidate)) {
				return candidate;
			}
		}

		return "";
	}

	function resetSession(cwd: string) {
		currentCwd = resolvePath(cwd, process.cwd());
		cwdAgentsPath = getAgentsFileFromDir(currentCwd);
		homeDir = resolvePath(os.homedir(), process.cwd());
		loadedAgents.clear();
		if (cwdAgentsPath) {
			loadedAgents.add(path.normalize(cwdAgentsPath));
		}
	}

	function findAgentsFiles(filePath: string, rootDir: string) {
		if (!rootDir) return [] as string[];

		const agentsFiles: string[] = [];
		let dir = path.dirname(filePath);

		while (isInsideRoot(rootDir, dir)) {
			const candidate = getAgentsFileFromDir(dir);
			if (candidate && candidate !== cwdAgentsPath) {
				agentsFiles.push(candidate);
			}

			if (dir === rootDir) break;

			const parent = path.dirname(dir);
			if (parent === dir) break;
			dir = parent;
		}

		return agentsFiles.reverse();
	}

	const handleSessionChange = (_event: unknown, ctx: ExtensionContext) => {
		resetSession(ctx.cwd);
	};

	pi.on("session_start", handleSessionChange);

	pi.on("tool_result", async (event, ctx) => {
		if (event.toolName !== "read" || event.isError) return undefined;

		const pathInput = event.input.path as string | undefined;
		if (!pathInput) return undefined;

		if (!currentCwd) resetSession(ctx.cwd);

		const absolutePath = resolvePath(pathInput, currentCwd);

		const searchRoot = isInsideRoot(currentCwd, absolutePath)
			? currentCwd
			: isInsideRoot(homeDir, absolutePath)
				? homeDir
				: "";
		if (!searchRoot) return undefined;

		if (AGENTS_FILENAMES.includes(path.basename(absolutePath))) {
			loadedAgents.add(path.normalize(absolutePath));
			return undefined;
		}

		const agentFiles = findAgentsFiles(absolutePath, searchRoot);
		const additions: TextContent[] = [];

		for (const agentsPath of agentFiles) {
			const normalizedAgentsPath = path.normalize(agentsPath);
			if (loadedAgents.has(normalizedAgentsPath)) continue;

			try {
				const content = await fs.promises.readFile(agentsPath, "utf-8");
				loadedAgents.add(normalizedAgentsPath);
				additions.push({
					type: "text",
					text: `Loaded subdirectory context from ${agentsPath}\n\n${content}`,
				});
			} catch (error) {
				if (ctx.hasUI) ctx.ui.notify(`Failed to load ${agentsPath}: ${String(error)}`, "warning");
			}
		}

		if (!additions.length) return undefined;

		const baseContent = event.content ?? [];
		return { content: [...baseContent, ...additions], details: event.details };
	});
}
