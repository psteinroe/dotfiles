import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type PrOptions = {
	stageAll: boolean;
	draft: boolean;
	fixes: string[];
	refs: string[];
	extraInstructions: string[];
	showHelp: boolean;
};

function tokenize(input: string): string[] {
	const tokens: string[] = [];
	let current = "";
	let quote: '"' | "'" | null = null;
	let escaped = false;

	for (const char of input) {
		if (escaped) {
			current += char;
			escaped = false;
			continue;
		}

		if (char === "\\") {
			escaped = true;
			continue;
		}

		if (quote) {
			if (char === quote) quote = null;
			else current += char;
			continue;
		}

		if (char === '"' || char === "'") {
			quote = char;
			continue;
		}

		if (/\s/.test(char)) {
			if (current) {
				tokens.push(current);
				current = "";
			}
			continue;
		}

		current += char;
	}

	if (escaped) current += "\\";
	if (current) tokens.push(current);
	return tokens;
}

function parseArgs(args: string): PrOptions {
	const options: PrOptions = {
		stageAll: false,
		draft: false,
		fixes: [],
		refs: [],
		extraInstructions: [],
		showHelp: false,
	};
	const tokens = tokenize(args);

	for (let i = 0; i < tokens.length; i += 1) {
		const token = tokens[i];

		if (token === "--help" || token === "-h") {
			options.showHelp = true;
			continue;
		}

		if (token === "--all" || token === "-a") {
			options.stageAll = true;
			continue;
		}

		if (token === "--draft" || token === "-d") {
			options.draft = true;
			continue;
		}

		if (token === "--fixes" || token === "-f") {
			const value = tokens[++i];
			if (value) options.fixes.push(value);
			else options.extraInstructions.push(`${token} was provided without a value; ask the user for the missing issue reference.`);
			continue;
		}

		if (token.startsWith("--fixes=")) {
			const value = token.slice("--fixes=".length);
			if (value) options.fixes.push(value);
			continue;
		}

		if (token === "--refs" || token === "-r") {
			const value = tokens[++i];
			if (value) options.refs.push(value);
			else options.extraInstructions.push(`${token} was provided without a value; ask the user for the missing issue reference.`);
			continue;
		}

		if (token.startsWith("--refs=")) {
			const value = token.slice("--refs=".length);
			if (value) options.refs.push(value);
			continue;
		}

		options.extraInstructions.push(token);
	}

	return options;
}

function buildPrompt(options: PrOptions): string {
	const lines = [
		"Use the `pr-writer` skill to create or refresh a GitHub pull request for the current branch.",
		"",
		"This `/pr` command invocation is explicit authorization to push the current branch if needed and to create a new PR or update the existing PR for this branch. Load and follow the `pr-writer` skill before acting.",
		"",
		"Operational constraints:",
		"- If the current branch already has a PR, update that PR's title/body instead of creating a duplicate.",
		"- If no PR exists, create a ready-for-review PR unless draft mode is requested below.",
	];

	if (options.stageAll) {
		lines.push(
			"- Stage-and-commit mode was requested with `--all`: if uncommitted changes exist, run `git add -A` and create an appropriate commit for those changes before pushing/creating/updating the PR.",
			"- If there are no uncommitted changes, continue with the existing committed branch state.",
		);
	} else {
		lines.push(
			"- Do not stage or commit uncommitted changes unless the user explicitly asks for that in this conversation.",
			"- If the working tree is dirty, pause and ask what to do.",
		);
	}

	if (options.draft) {
		lines.push("- Draft mode was requested: create a draft PR if a new PR is needed.");
	}

	if (options.fixes.length > 0) {
		lines.push(`- Add closing issue reference${options.fixes.length === 1 ? "" : "s"}: ${options.fixes.map((issue) => `Fixes ${issue}`).join(", ")}.`);
	}

	if (options.refs.length > 0) {
		lines.push(`- Add non-closing issue reference${options.refs.length === 1 ? "" : "s"}: ${options.refs.map((issue) => `Refs ${issue}`).join(", ")}.`);
	}

	if (options.extraInstructions.length > 0) {
		lines.push("", "Additional user-provided PR instructions:", options.extraInstructions.join(" "));
	}

	return lines.join("\n");
}

const HELP = `Usage: /pr [--all|-a] [--draft|-d] [--fixes|-f ISSUE] [--refs|-r ISSUE] [extra instructions]

Create or refresh a GitHub pull request for the current branch using the pr-writer skill.

Examples:
  /pr
  /pr --all
  /pr --draft
  /pr --fixes ABC-123
  /pr mention this is a follow-up to the auth refactor`;

export default function prExtension(pi: ExtensionAPI) {
	pi.registerCommand("pr", {
		description: "Create or refresh a PR for the current branch using pr-writer",
		handler: async (args, ctx) => {
			const options = parseArgs(args ?? "");

			if (options.showHelp) {
				ctx.ui.notify(HELP, "info");
				return;
			}

			ctx.ui.notify("Starting PR writer for the current branch", "info");
			pi.sendUserMessage(buildPrompt(options));
		},
	});
}
