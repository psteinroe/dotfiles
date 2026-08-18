import { Type } from "typebox";
import type { SubagentDetails, SubagentRunDetails } from "../shared/subagent-progress.ts";

export const DEFAULT_MAX_TURNS = 10;
export const DEFAULT_MAX_SEARCH_RESULTS = 30;

export const LibrarianParams = Type.Object({
  query: Type.String({
    description: [
      "Describe exactly what to find in GitHub code.",
      "Include known context in the query when you have it (e.g. symbols/behavior, repo or owner hints, ref/branch hints, path hints, and desired output).",
      "Do not guess unknown details; if scope is uncertain, say that explicitly and let Librarian discover it.",
      "The librarian returns concise path-first findings with line-ranged evidence from downloaded files.",
    ].join("\n"),
  }),
  repos: Type.Optional(
    Type.Array(Type.String({ description: "Optional owner/repo filters (e.g. octocat/hello-world)" }), {
      description: "Optional explicit repository scope.",
      maxItems: 30,
    }),
  ),
  owners: Type.Optional(
    Type.Array(Type.String({ description: "Optional owner/org filters" }), {
      description: "Optional owner/org scope.",
      maxItems: 30,
    }),
  ),
  maxSearchResults: Type.Optional(
    Type.Number({
      description: `Maximum GitHub search hits per query (1-100, default ${DEFAULT_MAX_SEARCH_RESULTS})`,
      minimum: 1,
      maximum: 100,
      default: DEFAULT_MAX_SEARCH_RESULTS,
    }),
  ),
});

export interface LibrarianMetadata {
  repos: string[];
  owners: string[];
  maxSearchResults: number;
}

export type LibrarianRunDetails = SubagentRunDetails;
export type LibrarianDetails = SubagentDetails<"librarian", "high", LibrarianMetadata>;

export interface NormalizedLibrarianParams {
  query: string;
  repos: string[];
  owners: string[];
  maxSearchResults: number;
}

export function asStringArray(value: unknown, maxItems = 30): string[] {
  if (!Array.isArray(value)) return [];
  const result: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") continue;
    const value = item.trim();
    if (!value) continue;
    result.push(value);
    if (result.length >= maxItems) break;
  }
  return result;
}

export function clampNumber(value: unknown, min: number, max: number, fallback: number): number {
  const number = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(number)));
}

export function normalizeLibrarianParams(params: unknown):
  | { value: NormalizedLibrarianParams }
  | { error: string } {
  const input = params as Record<string, unknown> | null | undefined;
  const query = typeof input?.query === "string" ? input.query.trim() : "";
  if (!query) return { error: "Invalid parameters: expected `query` to be a non-empty string." };

  return {
    value: {
      query,
      repos: asStringArray(input?.repos),
      owners: asStringArray(input?.owners),
      maxSearchResults: clampNumber(
        input?.maxSearchResults,
        1,
        100,
        DEFAULT_MAX_SEARCH_RESULTS,
      ),
    },
  };
}
