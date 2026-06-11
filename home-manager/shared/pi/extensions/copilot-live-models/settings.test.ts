import assert from "node:assert/strict";
import test from "node:test";
import { DEFAULT_CONTEXT_RESERVE_TOKENS } from "./constants.ts";
import { loadContextReserveTokens, parseContextReserveTokens } from "./settings.ts";

test("parseContextReserveTokens reads configured compaction reserve", () => {
  assert.equal(parseContextReserveTokens(JSON.stringify({ compaction: { reserveTokens: 128_000 } })), 128_000);
});

test("parseContextReserveTokens falls back for missing or invalid values", () => {
  assert.equal(parseContextReserveTokens(JSON.stringify({})), DEFAULT_CONTEXT_RESERVE_TOKENS);
  assert.equal(parseContextReserveTokens(JSON.stringify({ compaction: { reserveTokens: -1 } })), DEFAULT_CONTEXT_RESERVE_TOKENS);
});

test("loadContextReserveTokens falls back when settings cannot be read", async () => {
  const value = await loadContextReserveTokens("/tmp/pi-agent", async () => {
    throw new Error("missing");
  });

  assert.equal(value, DEFAULT_CONTEXT_RESERVE_TOKENS);
});
