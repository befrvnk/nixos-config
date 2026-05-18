import assert from "node:assert/strict";
import test from "node:test";
import { formatCodeSearchOutput, formatWebSearchOutput } from "./formatting.ts";
import { extractUrlsFromMcpResult } from "./url-extraction.ts";

test("formatWebSearchOutput emits only queries and source URLs", () => {
  const output = formatWebSearchOutput({
    originalQuery: "pi web_search formatting",
    plan: [{ label: "Official docs & references", query: "pi web_search docs" }],
    results: [
      {
        label: "Official docs & references",
        query: "pi web_search docs",
        urls: ["https://example.com/docs", "https://github.com/example/pi"],
      },
    ],
    warnings: [{ label: "Repo", query: "site:github.com pi", error: "timeout" }],
  });

  assert.match(output, /^# Web search sources/);
  assert.match(output, /\*\*Query:\*\* pi web_search formatting/);
  assert.match(output, /## Search queries/);
  assert.match(output, /- \*\*Official docs & references:\*\* `pi web_search docs`/);
  assert.match(output, /## Warnings/);
  assert.match(output, /## URLs/);
  assert.match(output, /### Official docs & references/);
  assert.match(output, /- https:\/\/example\.com\/docs/);
  assert.match(output, /- https:\/\/github\.com\/example\/pi/);
  assert.doesNotMatch(output, /Formatted item/);
  assert.doesNotMatch(output, /={20,}/);
});

test("extractUrlsFromMcpResult prefers search-result source URLs over page-content URLs", () => {
  const urls = extractUrlsFromMcpResult({
    content: [
      {
        type: "text",
        text: "Title: Result one\nURL: https://example.com/docs\nText: body mentions https://noise.example/internal\n\n## [Result two](https://github.com/example/project).\nText: more body",
      },
    ],
  });

  assert.deepEqual(urls, ["https://example.com/docs", "https://github.com/example/project"]);
});

test("extractUrlsFromMcpResult falls back to deduped URLs in text", () => {
  const urls = extractUrlsFromMcpResult({
    content: [{ type: "text", text: "See https:\\/\\/example.com\\/one and https://example.com/one." }],
  });

  assert.deepEqual(urls, ["https://example.com/one"]);
});

test("extractUrlsFromMcpResult extracts explicit nested URL fields", () => {
  const urls = extractUrlsFromMcpResult({
    content: [
      {
        type: "text",
        text: "Body mentions https://noise.example/internal but it is not a source URL.",
        metadata: {
          url: "https://example.com/result.",
          sourceUrl: "https://github.com/example/source",
        },
      },
    ],
  });

  assert.deepEqual(urls, ["https://example.com/result", "https://github.com/example/source"]);
});

test("extractUrlsFromMcpResult returns an empty list for nullish results", () => {
  assert.deepEqual(extractUrlsFromMcpResult(null), []);
  assert.deepEqual(extractUrlsFromMcpResult(undefined), []);
});

test("formatCodeSearchOutput emits readable markdown sections", () => {
  const output = formatCodeSearchOutput(
    "pi Markdown component example",
    5_000,
    42,
    "```ts\nnew Markdown(text, 0, 0, theme);\n```",
  );

  assert.match(output, /^# Code search/);
  assert.match(output, /\*\*Query:\*\* pi Markdown component example/);
  assert.match(output, /\*\*Max tokens:\*\* 5000/);
  assert.match(output, /\*\*Search time:\*\* 42ms/);
  assert.match(output, /```ts/);
});
