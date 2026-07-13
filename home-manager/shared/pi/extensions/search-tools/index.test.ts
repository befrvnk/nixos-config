import assert from "node:assert/strict";
import test from "node:test";
import { formatCodeSearchOutput, formatWebFetchOutput, formatWebSearchOutput } from "./formatting.ts";
import { extractUrlsFromMcpResult } from "./url-extraction.ts";
import { fetchWebUrl, formatFetchedContent, validatePublicWebUrl } from "./web-fetch.ts";

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

test("formatWebFetchOutput emits metadata and content", () => {
  const output = formatWebFetchOutput({
    originalUrl: "https://example.com/docs",
    finalUrl: "https://www.example.com/docs",
    status: 200,
    contentType: "text/html; charset=utf-8",
    format: "markdown",
    title: "Example Docs",
    bytes: 1234,
    maxCharacters: 20_000,
    truncated: false,
    content: "# Example\n\nFetched content",
    binary: false,
  });

  assert.match(output, /^# Web fetch/);
  assert.match(output, /\*\*URL:\*\* https:\/\/example\.com\/docs/);
  assert.match(output, /\*\*Final URL:\*\* https:\/\/www\.example\.com\/docs/);
  assert.match(output, /\*\*Title:\*\* Example Docs/);
  assert.match(output, /# Example/);
});

test("fetchWebUrl converts HTML to markdown and truncates content", async () => {
  const result = await fetchWebUrl(
    {
      url: "https://example.com/page",
      format: "markdown",
      maxCharacters: 80,
    },
    undefined,
    {
      resolveHostname: async () => ["93.184.216.34"],
      fetchImpl: async () =>
        new Response(
          '<html><head><title>Demo</title><script>bad()</script></head><body><h1>Hello</h1><p>See <a href="/docs">docs</a>.</p><p>Extra long content that should be truncated after the useful link.</p></body></html>',
          { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
        ),
    },
  );

  assert.equal(result.title, "Demo");
  assert.equal(result.truncated, true);
  assert.match(result.content, /^# Hello/);
  assert.match(result.content, /\[docs\]\(https:\/\/example\.com\/docs\)/);
  assert.doesNotMatch(result.content, /bad/);
});

test("formatFetchedContent safely handles malformed entities and controls", () => {
  assert.doesNotThrow(() => formatFetchedContent("<p>&#x110000; &#55296; &#27;</p>", "text/html", "text", "https://example.com"));
  const text = formatFetchedContent("<p>&#x110000; &#55296; &#27;</p>", "text/html", "text", "https://example.com");
  assert.doesNotMatch(text, /\u001b/u);
  assert.match(text, /�/u);

  const markdown = formatFetchedContent("<p>&lt;script&gt;safe&lt;/script&gt;</p>", "text/html", "markdown", "https://example.com");
  assert.match(markdown, /\\<script\\>/u);
});

test("fetchWebUrl rejects local and private URLs", async () => {
  await assert.rejects(() => validatePublicWebUrl("http://localhost/page"), /Localhost URLs are not allowed/);
  await assert.rejects(() => validatePublicWebUrl("http://127.0.0.1/page"), /Private, local, or reserved IP addresses/);
  await assert.rejects(
    () => validatePublicWebUrl("https://example.com/page", { resolveHostname: async () => ["10.0.0.10"] }),
    /resolves to a private, local, or reserved IP address/,
  );
  await assert.rejects(
    () => validatePublicWebUrl("https://example.com/page", { resolveHostname: async () => ["93.184.216.34", "127.0.0.1"] }),
    /resolves to a private, local, or reserved IP address/,
  );
  await assert.rejects(
    () => validatePublicWebUrl("https://example.com/page", { resolveHostname: async () => [] }),
    /did not resolve/,
  );
});

test("fetchWebUrl validates redirect targets before fetching them", async () => {
  let calls = 0;

  await assert.rejects(
    () =>
      fetchWebUrl(
        { url: "https://example.com/page", format: "text", maxCharacters: 1000 },
        undefined,
        {
          resolveHostname: async () => ["93.184.216.34"],
          fetchImpl: async () => {
            calls += 1;
            return new Response(null, { status: 302, headers: { location: "http://127.0.0.1/private" } });
          },
        },
      ),
    /Private, local, or reserved IP addresses/,
  );

  assert.equal(calls, 1);
});

test("fetchWebUrl preserves fractional timeout seconds", async () => {
  let observedTimeoutMs = 0;

  await fetchWebUrl(
    { url: "https://example.com/page", format: "text", timeoutSeconds: 1.9, maxCharacters: 1000 },
    undefined,
    {
      resolveHostname: async () => ["93.184.216.34"],
      createTimeoutSignal: ({ timeoutMs }) => {
        observedTimeoutMs = timeoutMs;
        return { signal: new AbortController().signal, clear: () => {} };
      },
      fetchImpl: async () => new Response("ok", { status: 200, headers: { "content-type": "text/plain" } }),
    },
  );

  assert.equal(observedTimeoutMs, 1900);
});

test("fetchWebUrl reports non-OK HTTP status codes", async () => {
  await assert.rejects(
    () =>
      fetchWebUrl(
        { url: "https://example.com/missing", format: "text", maxCharacters: 1000 },
        undefined,
        {
          resolveHostname: async () => ["93.184.216.34"],
          fetchImpl: async () => new Response("not found", { status: 404 }),
        },
      ),
    /Request failed with status code: 404/,
  );
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
