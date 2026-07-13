import assert from "node:assert/strict";
import test from "node:test";
import { DEFAULT_CONTEXT_RESERVE_TOKENS } from "./constants.ts";
import { loadContextReserveTokens, parseContextReserveTokens } from "./settings.ts";

test("parseContextReserveTokens reads JSONC compaction reserve", () => {
  assert.equal(parseContextReserveTokens(`{
    // Keep enough room for a full response.
    "compaction": { "reserveTokens": 128000, },
  }`), 128_000);
});

test("parseContextReserveTokens falls back for missing or invalid values", () => {
  const invalidValues = [
    undefined,
    "128000",
    0,
    -1,
    1.5,
    Number.NaN,
    Number.POSITIVE_INFINITY,
    Number.MAX_SAFE_INTEGER + 1,
  ];

  assert.equal(parseContextReserveTokens(JSON.stringify({})), DEFAULT_CONTEXT_RESERVE_TOKENS);
  assert.equal(parseContextReserveTokens("null"), DEFAULT_CONTEXT_RESERVE_TOKENS);
  assert.equal(parseContextReserveTokens("[]"), DEFAULT_CONTEXT_RESERVE_TOKENS);
  assert.equal(parseContextReserveTokens('{"compaction": null}'), DEFAULT_CONTEXT_RESERVE_TOKENS);
  for (const reserveTokens of invalidValues) {
    assert.equal(
      parseContextReserveTokens(JSON.stringify({ compaction: { reserveTokens } })),
      DEFAULT_CONTEXT_RESERVE_TOKENS,
    );
  }
});

test("loadContextReserveTokens falls back when settings are malformed", async () => {
  const value = await loadContextReserveTokens("/tmp/pi-agent", async () => "{ not jsonc }");
  assert.equal(value, DEFAULT_CONTEXT_RESERVE_TOKENS);
});

test("loadContextReserveTokens falls back when settings cannot be read", async () => {
  const value = await loadContextReserveTokens("/tmp/pi-agent", async () => {
    throw new Error("missing");
  });

  assert.equal(value, DEFAULT_CONTEXT_RESERVE_TOKENS);
});
