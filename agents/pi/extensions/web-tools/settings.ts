import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import {
	type SearchDepth,
	type SearchProviderName,
	type WebFetchFormat,
	type WebToolsSettings,
} from "./types.ts";

const FETCH_DEFAULT_FORMAT_VALUES = ["markdown", "text", "html"] as const satisfies readonly WebFetchFormat[];
const SEARCH_PROVIDER_VALUES = ["exa"] as const satisfies readonly SearchProviderName[];
const SEARCH_DEFAULT_DEPTH_VALUES = ["auto", "fast", "deep"] as const satisfies readonly SearchDepth[];

const DEFAULTS = {
	fetchDefaultFormat: "markdown",
	fetchTimeoutSeconds: 30,
	fetchMaxResponseMB: 5,
	fetchBlockPrivateHosts: true,
	fetchMaxRedirects: 5,
	fetchFallbackUserAgent: "pi",
	searchEnabled: true,
	searchProvider: "exa",
	searchEndpoint: "https://mcp.exa.ai/mcp",
	searchTimeoutSeconds: 25,
	searchDefaultMaxResults: 8,
	searchDefaultDepth: "auto",
} as const;

export function parseOnOff(value: string | undefined, fallback: boolean): boolean {
	if (!value) return fallback;
	const normalized = value.trim().toLowerCase();
	if (normalized === "on") return true;
	if (normalized === "off") return false;
	return fallback;
}

export function parseIntegerSetting(
	value: string | undefined,
	fallback: number,
	options: { min?: number; max?: number } = {},
): number {
	const parsed = Number.parseInt(value?.trim() ?? "", 10);
	if (!Number.isFinite(parsed)) return fallback;
	if (options.min !== undefined && parsed < options.min) return fallback;
	if (options.max !== undefined && parsed > options.max) return fallback;
	return parsed;
}

export function parseEnumSetting<T extends string>(
	value: string | undefined,
	allowed: readonly T[],
	fallback: T,
): T {
	if (!value) return fallback;
	const normalized = value.trim() as T;
	return allowed.includes(normalized) ? normalized : fallback;
}

function readKeychainEnvironmentVariable(name: string): string | undefined {
	if (process.platform !== "darwin") return undefined;
	try {
		return execFileSync("security", [
			"find-generic-password",
			"-w",
			"-a",
			os.userInfo().username,
			"-D",
			"environment variable",
			"-s",
			name,
		], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim() || undefined;
	} catch {
		return undefined;
	}
}

function readSecretFile(filePath: string | undefined): string | undefined {
	if (!filePath) return undefined;
	try {
		return readFileSync(filePath, "utf8").trim() || undefined;
	} catch {
		return undefined;
	}
}

function readDefaultExaApiKeyFile(): string | undefined {
	const configHome = process.env.XDG_CONFIG_HOME?.trim() || path.join(os.homedir(), ".config");
	return readSecretFile(path.join(configHome, "exa", "api_key"));
}

function readExaApiKey(): string | undefined {
	return process.env.EXA_API_KEY?.trim()
		|| process.env.EXA_API_TOKEN?.trim()
		|| readSecretFile(process.env.EXA_API_KEY_FILE?.trim())
		|| readKeychainEnvironmentVariable("EXA_API_KEY")
		|| readKeychainEnvironmentVariable("EXA_API_TOKEN")
		|| readDefaultExaApiKeyFile();
}

export function getWebToolsSettings(): WebToolsSettings {
	const fetchDefaultFormat = parseEnumSetting(undefined, FETCH_DEFAULT_FORMAT_VALUES, DEFAULTS.fetchDefaultFormat);
	const searchProvider = parseEnumSetting(undefined, SEARCH_PROVIDER_VALUES, DEFAULTS.searchProvider);
	const searchDefaultDepth = parseEnumSetting(undefined, SEARCH_DEFAULT_DEPTH_VALUES, DEFAULTS.searchDefaultDepth);

	return {
		fetch: {
			defaultFormat: fetchDefaultFormat,
			timeoutSeconds: DEFAULTS.fetchTimeoutSeconds,
			maxResponseBytes: DEFAULTS.fetchMaxResponseMB * 1024 * 1024,
			blockPrivateHosts: DEFAULTS.fetchBlockPrivateHosts,
			maxRedirects: DEFAULTS.fetchMaxRedirects,
			fallbackUserAgent: DEFAULTS.fetchFallbackUserAgent,
		},
		search: {
			enabled: DEFAULTS.searchEnabled,
			provider: searchProvider,
			endpoint: process.env.EXA_MCP_URL?.trim() || DEFAULTS.searchEndpoint,
			apiKey: readExaApiKey(),
			timeoutSeconds: DEFAULTS.searchTimeoutSeconds,
			defaultMaxResults: DEFAULTS.searchDefaultMaxResults,
			defaultDepth: searchDefaultDepth,
		},
	};
}
