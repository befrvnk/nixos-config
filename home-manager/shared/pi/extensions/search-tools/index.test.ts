import assert from "node:assert/strict";
import test from "node:test";
import { formatCodeSearchOutput, formatWebSearchOutput } from "./formatting.ts";

test("formatWebSearchOutput emits readable markdown sections", () => {
  const output = formatWebSearchOutput({
    originalQuery: "pi web_search formatting",
    mode: "overview",
    focus: "docs",
    settings: {
      results: 3,
      depth: "auto",
      freshness: "fallback",
      maxCharacters: 4_000,
    },
    plan: [{ label: "Official docs & references", query: "pi web_search docs" }],
    results: [
      {
        label: "Official docs & references",
        query: "pi web_search docs",
        searchTime: 12.34,
        text: "### Example result\n\n- Formatted item",
      },
    ],
    warnings: [{ label: "Repo", query: "site:github.com pi", error: "timeout" }],
    currentYearInjected: true,
  });

  assert.match(output, /^# Web research overview/);
  assert.match(output, /\*\*Query:\*\* pi web_search formatting/);
  assert.match(output, /## Search plan/);
  assert.match(output, /- \*\*Official docs & references:\*\* `pi web_search docs`/);
  assert.match(output, /## Warnings/);
  assert.match(output, /## Official docs & references/);
  assert.match(output, /### Example result/);
  assert.doesNotMatch(output, /={20,}/);
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
