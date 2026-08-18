import assert from "node:assert/strict";
import test from "node:test";
import {
  DEFAULT_MAX_SEARCH_RESULTS,
  LibrarianParams,
  normalizeLibrarianParams,
} from "./core.ts";

test("preserves the public librarian parameter schema", () => {
  const schema = LibrarianParams as any;
  assert.equal(schema.type, "object");
  assert.equal(schema.properties.query.type, "string");
  assert.equal(schema.properties.repos.maxItems, 30);
  assert.equal(schema.properties.owners.maxItems, 30);
  assert.equal(schema.properties.maxSearchResults.minimum, 1);
  assert.equal(schema.properties.maxSearchResults.maximum, 100);
  assert.equal(schema.properties.maxSearchResults.default, DEFAULT_MAX_SEARCH_RESULTS);
});

test("normalizes query, scopes, and search limit like upstream", () => {
  const result = normalizeLibrarianParams({
    query: "  find the thing  ",
    repos: [" octocat/hello-world ", "", 42, "second"],
    owners: [" octocat ", " ", "acme"],
    maxSearchResults: 42.9,
  });
  assert.deepEqual(result, {
    value: {
      query: "find the thing",
      repos: ["octocat/hello-world", "second"],
      owners: ["octocat", "acme"],
      maxSearchResults: 42,
    },
  });
  assert.deepEqual(normalizeLibrarianParams({ query: "x", maxSearchResults: 1000 }), {
    value: { query: "x", repos: [], owners: [], maxSearchResults: 100 },
  });
  assert.deepEqual(normalizeLibrarianParams({ query: "  " }), {
    error: "Invalid parameters: expected `query` to be a non-empty string.",
  });
});
