import assert from "node:assert/strict";
import { mkdir, mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import installSubdirContext from "./index.ts";

type Handler = (event: any, context: any) => any;

function createHarness(cwd: string) {
	const handlers = new Map<string, Handler[]>();
	const notifications: Array<{ message: string; level: string }> = [];
	const pi = {
		on(name: string, handler: Handler) {
			handlers.set(name, [...(handlers.get(name) ?? []), handler]);
		},
	};
	const context = {
		cwd,
		hasUI: true,
		ui: {
			notify(message: string, level: string) {
				notifications.push({ message, level });
			},
		},
	};

	installSubdirContext(pi as any);
	return { context, handlers, notifications };
}

async function emit(
	handlers: Map<string, Handler[]>,
	name: string,
	event: any,
	context: any,
) {
	let result;
	for (const handler of handlers.get(name) ?? []) {
		result = await handler(event, context);
	}
	return result;
}

async function readResult(
	harness: ReturnType<typeof createHarness>,
	readPath: string,
	extra: Record<string, unknown> = {},
) {
	return emit(
		harness.handlers,
		"tool_result",
		{
			toolName: "read",
			isError: false,
			input: { path: readPath },
			content: [{ type: "text", text: "original read result" }],
			details: { fixture: true },
			...extra,
		},
		harness.context,
	);
}

function additions(result: any): string[] {
	return (result?.content ?? []).slice(1).map((item: any) => item.text);
}

async function withTempDir(run: (directory: string) => Promise<void>) {
	const directory = await mkdtemp(path.join(os.tmpdir(), "pi-subdir-context-"));
	try {
		await run(directory);
	} finally {
		await rm(directory, { recursive: true, force: true });
	}
}

test("uses per-directory precedence and appends contexts from root to leaf", async () => {
	await withTempDir(async (directory) => {
		const cwdPath = path.join(directory, "project");
		await mkdir(cwdPath, { recursive: true });
		const cwd = await realpath(cwdPath);
		const overrideDir = path.join(cwd, "override", "leaf");
		const agentsDir = path.join(cwd, "agents", "leaf");
		const claudeDir = path.join(cwd, "claude", "leaf");
		await mkdir(overrideDir, { recursive: true });
		await mkdir(agentsDir, { recursive: true });
		await mkdir(claudeDir, { recursive: true });
		await writeFile(path.join(cwd, "override", "AGENTS.override.md"), "override");
		await writeFile(path.join(cwd, "override", "AGENTS.md"), "wrong agents");
		await writeFile(path.join(cwd, "override", "CLAUDE.md"), "wrong claude");
		await writeFile(path.join(cwd, "agents", "AGENTS.md"), "agents");
		await writeFile(path.join(cwd, "agents", "CLAUDE.md"), "wrong claude");
		await writeFile(path.join(cwd, "claude", "CLAUDE.md"), "claude");
		for (const target of [overrideDir, agentsDir, claudeDir]) {
			await writeFile(path.join(target, "file.txt"), "file");
		}

		const harness = createHarness(cwd);
		await emit(harness.handlers, "session_start", {}, harness.context);

		const overrideResult = await readResult(harness, "override/leaf/file.txt");
		assert.deepEqual(additions(overrideResult), [
			`Loaded subdirectory context from ${path.join(cwd, "override", "AGENTS.override.md")}\n\noverride`,
		]);
		assert.deepEqual(overrideResult.content[0], {
			type: "text",
			text: "original read result",
		});
		assert.deepEqual(overrideResult.details, { fixture: true });

		const agentsResult = await readResult(harness, "agents/leaf/file.txt");
		assert.deepEqual(additions(agentsResult), [
			`Loaded subdirectory context from ${path.join(cwd, "agents", "AGENTS.md")}\n\nagents`,
		]);

		const claudeResult = await readResult(harness, "claude/leaf/file.txt");
		assert.deepEqual(additions(claudeResult), [
			`Loaded subdirectory context from ${path.join(cwd, "claude", "CLAUDE.md")}\n\nclaude`,
		]);

		const orderedRoot = path.join(cwd, "ordered", "nested");
		await mkdir(orderedRoot, { recursive: true });
		await writeFile(path.join(cwd, "ordered", "AGENTS.md"), "ordered root");
		await writeFile(path.join(orderedRoot, "CLAUDE.md"), "ordered leaf");
		await writeFile(path.join(orderedRoot, "file.txt"), "file");
		const orderedResult = await readResult(harness, "ordered/nested/file.txt");
		assert.deepEqual(additions(orderedResult), [
			`Loaded subdirectory context from ${path.join(cwd, "ordered", "AGENTS.md")}\n\nordered root`,
			`Loaded subdirectory context from ${path.join(orderedRoot, "CLAUDE.md")}\n\nordered leaf`,
		]);
	});
});

test("deduplicates loaded contexts and resets the dedupe set per session", async () => {
	await withTempDir(async (directory) => {
		const cwd = path.join(directory, "project");
		const leaf = path.join(cwd, "sub", "leaf");
		await mkdir(leaf, { recursive: true });
		await writeFile(path.join(cwd, "sub", "AGENTS.md"), "sub context");
		await writeFile(path.join(leaf, "file.txt"), "file");

		const harness = createHarness(cwd);
		await emit(harness.handlers, "session_start", {}, harness.context);
		assert.equal(additions(await readResult(harness, "sub/leaf/file.txt")).length, 1);
		assert.equal(await readResult(harness, "sub/leaf/file.txt"), undefined);

		await emit(harness.handlers, "session_start", {}, harness.context);
		assert.equal(additions(await readResult(harness, "sub/leaf/file.txt")).length, 1);
	});
});

test("confines context discovery to cwd or home, including real paths", async () => {
	await withTempDir(async (directory) => {
		const cwd = path.join(directory, "project");
		const outside = path.join(directory, "outside");
		await mkdir(cwd, { recursive: true });
		await mkdir(outside, { recursive: true });
		await writeFile(path.join(outside, "AGENTS.md"), "outside context");
		await writeFile(path.join(outside, "file.txt"), "file");
		const harness = createHarness(cwd);
		await emit(harness.handlers, "session_start", {}, harness.context);
		assert.equal(await readResult(harness, "../outside/file.txt"), undefined);

		const link = path.join(cwd, "link");
		await (await import("node:fs/promises")).symlink(outside, link, "dir");
		assert.equal(await readResult(harness, "link/file.txt"), undefined);
	});

	const homeFixture = await mkdtemp(path.join(os.homedir(), ".pi-subdir-context-"));
	try {
		const cwd = path.join(homeFixture, "project");
		const homeSubdir = path.join(homeFixture, "sibling", "leaf");
		await mkdir(cwd, { recursive: true });
		await mkdir(homeSubdir, { recursive: true });
		await writeFile(path.join(homeFixture, "sibling", "AGENTS.md"), "home context");
		await writeFile(path.join(homeSubdir, "file.txt"), "file");
		const harness = createHarness(cwd);
		await emit(harness.handlers, "session_start", {}, harness.context);
		const result = await readResult(harness, path.join(homeSubdir, "file.txt"));
		assert.deepEqual(additions(result), [
			`Loaded subdirectory context from ${path.join(homeFixture, "sibling", "AGENTS.md")}\n\nhome context`,
		]);
	} finally {
		await rm(homeFixture, { recursive: true, force: true });
	}
});

test("ignores failed and non-read results", async () => {
	await withTempDir(async (directory) => {
		const harness = createHarness(path.join(directory, "project"));
		await mkdir(harness.context.cwd, { recursive: true });
		await emit(harness.handlers, "session_start", {}, harness.context);
		assert.equal(
			await emit(
				harness.handlers,
				"tool_result",
				{ toolName: "bash", isError: false, input: { path: "file.txt" } },
				harness.context,
			),
			undefined,
		);
		assert.equal(
			await readResult(harness, "file.txt", { isError: true }),
			undefined,
		);
		assert.equal(
			await emit(
				harness.handlers,
				"tool_result",
				{ toolName: "read", isError: false, input: {} },
				harness.context,
			),
			undefined,
		);
	});
});

test("does not inject manually read context files", async () => {
	await withTempDir(async (directory) => {
		const cwd = path.join(directory, "project");
		const contextDir = path.join(cwd, "sub", "leaf");
		await mkdir(contextDir, { recursive: true });
		const contextPath = path.join(cwd, "sub", "AGENTS.md");
		const targetPath = path.join(contextDir, "file.txt");
		await writeFile(contextPath, "already read");
		await writeFile(targetPath, "file");

		const harness = createHarness(cwd);
		await emit(harness.handlers, "session_start", {}, harness.context);
		assert.equal(await readResult(harness, "sub/AGENTS.md"), undefined);
		assert.equal(await readResult(harness, "sub/leaf/file.txt"), undefined);
	});
});

test("notifies when a discovered context file cannot be read", async () => {
	await withTempDir(async (directory) => {
		const cwdPath = path.join(directory, "project");
		await mkdir(cwdPath, { recursive: true });
		const cwd = await realpath(cwdPath);
		const leaf = path.join(cwd, "sub", "leaf");
		await mkdir(path.join(cwd, "sub", "AGENTS.md"), { recursive: true });
		await mkdir(leaf, { recursive: true });
		await writeFile(path.join(leaf, "file.txt"), "file");

		const harness = createHarness(cwd);
		await emit(harness.handlers, "session_start", {}, harness.context);
		assert.equal(await readResult(harness, "sub/leaf/file.txt"), undefined);
		assert.deepEqual(harness.notifications, [
			{
				message: `Failed to load ${path.join(cwd, "sub", "AGENTS.md")}: Error: EISDIR: illegal operation on a directory, read`,
				level: "warning",
			},
		]);
	});
});
