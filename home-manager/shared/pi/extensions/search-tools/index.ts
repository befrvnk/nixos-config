import { StringEnum, Type } from "@mariozechner/pi-ai";
import {
  defineTool,
  getMarkdownTheme,
  type ExtensionAPI,
} from "@mariozechner/pi-coding-agent";
import { Markdown, Text } from "@mariozechner/pi-tui";
import { formatCodeSearchOutput, formatWebFetchOutput, formatWebFetchSummaryOutput, formatWebSearchOutput } from "./formatting.ts";
import { extractUrlsFromMcpResult } from "./url-extraction.ts";
import { fetchWebUrl, type WebFetchFormat } from "./web-fetch.ts";

const EXA_MCP_URL = process.env.EXA_MCP_URL ?? "https://mcp.exa.ai/mcp";
const EXA_RETRIES = readPositiveIntEnv(["EXA_RETRIES", "EXA_CURL_RETRIES"], 2);
const EXA_RETRY_DELAY_MS = 1_000;
const MAX_CONCURRENCY = 2;

const WebSearchMode = StringEnum(["overview", "single"] as const, {
  description:
    'Search mode. "overview" runs a multi-pass research workflow. "single" runs only the exact query.',
  default: "overview",
});

const WebSearchFocus = StringEnum(["overview", "docs", "general", "repo", "recent"] as const, {
  description:
    'Overview focus. Use "docs" for official docs/API references, "repo" for GitHub/releases/issues, "recent" for latest/current changes, "general" for one broad web pass, or "overview" for the default multi-pass plan.',
  default: "overview",
});

const SearchDepth = StringEnum(["auto", "fast", "deep"] as const, {
  description: 'Search depth. Leave omitted for adaptive defaults; use "deep" for broader research.',
});

const SearchFreshness = StringEnum(["fallback", "prefer_fresh"] as const, {
  description:
    'Freshness preference. Leave omitted for adaptive defaults; use "prefer_fresh" for recent/current/release/changelog queries.',
});

const WebFetchFormatEnum = StringEnum(["markdown", "text", "html"] as const, {
  description: 'Response format to return. Defaults to "markdown".',
  default: "markdown",
});

type WebSearchModeValue = "overview" | "single";
type WebSearchFocusValue = "overview" | "docs" | "general" | "repo" | "recent";
type SearchDepthValue = "auto" | "fast" | "deep";
type SearchFreshnessValue = "fallback" | "prefer_fresh";
type ExaLivecrawl = "fallback" | "preferred";

interface SearchSettings {
  results: number;
  depth: SearchDepthValue;
  livecrawl: ExaLivecrawl;
  freshness: SearchFreshnessValue;
  maxCharacters: number;
}

interface SearchPlanItem {
  label: string;
  query: string;
}

interface SearchResult extends SearchPlanItem {
  urls: string[];
}

interface SearchWarning {
  label: string;
  query: string;
  error: string;
}

const webSearchTool = defineTool({
  name: "web_search",
  label: "Web Search",
  description:
    "Search the web for current documentation, official references, release notes, recent changes, project pages, issues, and technical information beyond the model cutoff. Returns searched queries and source URLs, not page content.",
  promptSnippet:
    "Search the web for current docs, release notes, official pages, recent changes, GitHub/project information, and technical source URLs",
  promptGuidelines: [
    "Use web_search when the user asks for current documentation, release notes, recent changes, official project pages, web research, or information beyond the model cutoff.",
    "Use web_search with focus='docs' for official documentation and API references.",
    "Use web_search with focus='repo' for GitHub repositories, changelogs, releases, and issues.",
    "Use web_search with focus='recent' for latest/current/release/changelog questions.",
    "Use web_search in default overview mode first when the user needs a broad understanding of a project, library, or tool.",
    "web_search returns source URLs only; use web_fetch on a specific URL if page content is required.",
    "Preserve user constraints such as site:, repository names, versions, and years in web_search queries.",
  ],
  parameters: Type.Object({
    query: Type.String({ description: "Search query. Preserve user constraints such as site:, repo names, versions, and years." }),
    mode: Type.Optional(WebSearchMode),
    focus: Type.Optional(WebSearchFocus),
    results: Type.Optional(
      Type.Number({
        description: "Number of results per search pass. Leave omitted for adaptive defaults.",
        minimum: 1,
      }),
    ),
    depth: Type.Optional(SearchDepth),
    freshness: Type.Optional(SearchFreshness),
    maxCharacters: Type.Optional(
      Type.Number({
        description: "Maximum context characters per search pass. Leave omitted for adaptive defaults.",
        minimum: 1,
      }),
    ),
  }),

  renderCall(args, theme) {
    const query = typeof args.query === "string" ? args.query.trim() : "";
    const mode = typeof args.mode === "string" ? args.mode : "overview";
    const focus = typeof args.focus === "string" ? args.focus : "overview";
    let text = `${theme.fg("toolTitle", theme.bold("Web Search"))} `;
    text += theme.fg("accent", query || "query");
    if (mode !== "overview" || focus !== "overview") {
      text += theme.fg("muted", ` (${mode}/${focus})`);
    }
    return new Text(text, 0, 0);
  },

  renderResult(result, options) {
    return renderMarkdownToolResult(result, options, "Searching the web…", "No web results found.");
  },

  async execute(_toolCallId, params, signal) {
    const query = params.query.trim();
    if (!query) {
      throw new Error("web_search requires a non-empty query.");
    }

    const mode = (params.mode ?? "overview") as WebSearchModeValue;
    const focus = (params.focus ?? "overview") as WebSearchFocusValue;
    const settings = resolveWebSearchSettings({
      mode,
      focus,
      results: params.results,
      depth: params.depth as SearchDepthValue | undefined,
      freshness: params.freshness as SearchFreshnessValue | undefined,
      maxCharacters: params.maxCharacters,
    });

    const { plan, topicQuery, siteFilters, currentYearInjected } = buildSearchPlan(query, mode, focus);

    const { results, warnings } = await runSearchPlan(plan, settings, signal);
    if (results.length === 0) {
      const warningText = warnings.map((warning) => `${warning.label}: ${warning.error}`).join("\n");
      throw new Error(`All web_search passes failed.${warningText ? `\n${warningText}` : ""}`);
    }

    const text = formatWebSearchOutput({
      originalQuery: query,
      plan,
      results,
      warnings,
    });

    return {
      content: [{ type: "text", text }],
      details: {
        originalQuery: query,
        topicQuery,
        mode,
        focus,
        settings: {
          depth: settings.depth,
          freshness: settings.freshness,
          resultsPerSearch: settings.results,
          maxCharactersPerSearch: settings.maxCharacters,
          provider: {
            name: "exa",
            tool: "web_search_exa",
            type: settings.depth,
            livecrawl: settings.livecrawl,
          },
        },
        siteFilters,
        currentYearInjected,
        searches: results,
        warnings,
      },
    };
  },
});

const webFetchTool = defineTool({
  name: "web_fetch",
  label: "Web Fetch",
  description:
    "Fetch the content of a specific HTTP(S) URL discovered through web_search or provided by the user. Returns markdown, text, or HTML with metadata and truncation.",
  promptSnippet: "Fetch and read the content of a specific HTTP(S) URL when source content is needed",
  promptGuidelines: [
    "Use web_fetch after web_search when you need to inspect the content of a specific source URL.",
    "Prefer fetching official documentation, repository, changelog, or release-note URLs before less authoritative sources.",
    "Do not use web_fetch for local files or internal/private network URLs; only HTTP(S) web URLs are supported.",
    "Keep maxCharacters as small as practical; increase it only when the page content is incomplete for the task.",
  ],
  parameters: Type.Object({
    url: Type.String({ description: "HTTP(S) URL to fetch. Use a specific source URL, not a search query." }),
    format: Type.Optional(WebFetchFormatEnum),
    timeout: Type.Optional(
      Type.Number({
        description: "Optional timeout in seconds. Default: 30. Maximum: 120.",
        minimum: 1,
        maximum: 120,
      }),
    ),
    maxCharacters: Type.Optional(
      Type.Number({
        description: "Maximum characters of fetched content to return. Default: 20000.",
        minimum: 1,
        maximum: 200000,
      }),
    ),
  }),

  renderCall(args, theme) {
    const url = typeof args.url === "string" ? args.url.trim() : "";
    const format = typeof args.format === "string" ? args.format : "markdown";
    let text = `${theme.fg("toolTitle", theme.bold("Web Fetch"))} `;
    text += theme.fg("accent", url || "url");
    if (format !== "markdown") text += theme.fg("muted", ` (${format})`);
    return new Text(text, 0, 0);
  },

  renderResult(result, options) {
    if (
      !options.isPartial &&
      result.details &&
      typeof result.details === "object" &&
      ("originalUrl" in result.details || "finalUrl" in result.details)
    ) {
      return new Markdown(formatWebFetchSummaryOutput(result.details), 0, 0, getMarkdownTheme());
    }
    return renderMarkdownToolResult(result, options, "Fetching URL…", "No web content fetched.");
  },

  async execute(_toolCallId, params, signal) {
    const maxCharacters = Math.trunc(params.maxCharacters ?? 20_000);
    if (maxCharacters < 1 || maxCharacters > 200_000) {
      throw new Error("web_fetch maxCharacters must be between 1 and 200000.");
    }

    const timeout = params.timeout == null ? undefined : params.timeout;
    if (timeout != null && (timeout < 1 || timeout > 120)) {
      throw new Error("web_fetch timeout must be between 1 and 120 seconds.");
    }

    const result = await fetchWebUrl(
      {
        url: params.url,
        format: (params.format ?? "markdown") as WebFetchFormat,
        timeoutSeconds: timeout,
        maxCharacters,
      },
      signal,
    );
    const text = formatWebFetchOutput(result);

    return {
      content: [{ type: "text", text }],
      details: result,
    };
  },
});

const codeSearchTool = defineTool({
  name: "code_search",
  label: "Code Search",
  description:
    "Search implementation-oriented API, SDK, framework, and library documentation with code examples. Use for usage patterns, configuration examples, and code-context lookups.",
  promptSnippet:
    "Find implementation-oriented API, SDK, framework, and library docs with code examples and usage patterns",
  promptGuidelines: [
    "Use code_search for implementation-oriented API, SDK, library, or framework usage examples.",
    "Use code_search when the user asks how to configure or call a library/API and web_search would be too general.",
    "Prefer local repository tools such as grep/find/LSP for searching the current codebase; use code_search for external docs and code context.",
  ],
  parameters: Type.Object({
    query: Type.String({ description: "Implementation-oriented search query, such as an API, framework feature, or configuration task." }),
    maxTokens: Type.Optional(
      Type.Number({
        description: "Maximum code-context tokens to return. Default: 5000. Valid range: 1000-50000.",
        minimum: 1000,
        maximum: 50000,
      }),
    ),
  }),

  renderCall(args, theme) {
    const query = typeof args.query === "string" ? args.query.trim() : "";
    const maxTokens = typeof args.maxTokens === "number" ? args.maxTokens : undefined;
    let text = `${theme.fg("toolTitle", theme.bold("Code Search"))} `;
    text += theme.fg("accent", query || "query");
    if (maxTokens != null) text += theme.fg("muted", ` (${maxTokens} tokens)`);
    return new Text(text, 0, 0);
  },

  renderResult(result, options) {
    return renderMarkdownToolResult(result, options, "Searching code context…", "No code snippets or documentation found.");
  },

  async execute(_toolCallId, params, signal) {
    const query = params.query.trim();
    if (!query) {
      throw new Error("code_search requires a non-empty query.");
    }

    const maxTokens = Math.trunc(params.maxTokens ?? 5_000);
    if (maxTokens < 1_000 || maxTokens > 50_000) {
      throw new Error("code_search maxTokens must be between 1000 and 50000.");
    }

    const event = await callExaMcpWithRetries("get_code_context_exa", { query, tokensNum: maxTokens }, 35_000, signal);
    const searchTime = event?.result?.content?.[0]?._meta?.searchTime ?? null;
    const resultText = event?.result?.content?.[0]?.text ?? "";
    const text = formatCodeSearchOutput(query, maxTokens, searchTime, resultText);

    return {
      content: [{ type: "text", text }],
      details: {
        query,
        maxTokens,
        searchTime,
        text: resultText,
        provider: {
          name: "exa",
          tool: "get_code_context_exa",
        },
      },
    };
  },
});

export default function searchToolsExtension(pi: ExtensionAPI) {
  pi.registerTool(webSearchTool);
  pi.registerTool(webFetchTool);
  pi.registerTool(codeSearchTool);
}

function resolveWebSearchSettings(params: {
  mode: WebSearchModeValue;
  focus: WebSearchFocusValue;
  results?: number;
  depth?: SearchDepthValue;
  freshness?: SearchFreshnessValue;
  maxCharacters?: number;
}): SearchSettings {
  const defaults = getWebSearchDefaults(params.mode, params.focus);
  const results = Math.trunc(params.results ?? defaults.results);
  const maxCharacters = Math.trunc(params.maxCharacters ?? defaults.maxCharacters);
  const depth = params.depth ?? defaults.depth;
  const freshness = params.freshness ?? defaults.freshness;

  if (results < 1) throw new Error("web_search results must be at least 1.");
  if (maxCharacters < 1) throw new Error("web_search maxCharacters must be at least 1.");

  return {
    results,
    depth,
    freshness,
    livecrawl: freshnessToLivecrawl(freshness),
    maxCharacters,
  };
}

function getWebSearchDefaults(mode: WebSearchModeValue, focus: WebSearchFocusValue): Omit<SearchSettings, "livecrawl"> {
  if (mode === "single") {
    return { results: 8, depth: "auto", freshness: "fallback", maxCharacters: 6_000 };
  }

  if (focus === "overview") {
    return { results: 5, depth: "deep", freshness: "prefer_fresh", maxCharacters: 8_000 };
  }

  if (focus === "recent") {
    return { results: 6, depth: "auto", freshness: "prefer_fresh", maxCharacters: 8_000 };
  }

  return { results: 8, depth: "auto", freshness: "fallback", maxCharacters: 6_000 };
}

function freshnessToLivecrawl(freshness: SearchFreshnessValue): ExaLivecrawl {
  return freshness === "prefer_fresh" ? "preferred" : "fallback";
}

function buildSearchPlan(
  query: string,
  mode: WebSearchModeValue,
  focus: WebSearchFocusValue,
): { plan: SearchPlanItem[]; topicQuery: string; siteFilters: string[]; currentYearInjected: boolean } {
  const topicQuery = normalizeTopicQuery(query) || query;
  const siteFilters = extractSiteFilters(query);
  const plan: SearchPlanItem[] = [];
  let currentYearInjected = false;

  if (mode === "single") {
    return {
      plan: [{ label: "Focused search", query }],
      topicQuery,
      siteFilters,
      currentYearInjected,
    };
  }

  const docsQuery = `${query} official documentation docs reference`;
  const generalQuery = query;
  const repoQuery = hasGithubConstraint(query)
    ? `${query} releases issues changelog`
    : `site:github.com ${topicQuery} releases issues changelog`;
  const recentBase = `${query} latest updates announcements release notes`;
  const recentQuery = appendRecentYearIfNeeded(recentBase);

  const add = (label: string, searchQuery: string) => plan.push({ label, query: searchQuery });

  switch (focus) {
    case "overview":
      add("Official docs & references", docsQuery);
      add("General overview", generalQuery);
      add("Code, releases & issues", repoQuery);
      if (isRecencySensitive(query)) {
        add("Recent updates", recentQuery);
        currentYearInjected = !hasYearToken(recentBase);
      }
      break;
    case "docs":
      add("Official docs & references", docsQuery);
      break;
    case "general":
      add("General overview", generalQuery);
      break;
    case "repo":
      add("Code, releases & issues", repoQuery);
      break;
    case "recent":
      add("Recent updates", recentQuery);
      currentYearInjected = !hasYearToken(recentBase);
      break;
  }

  return { plan, topicQuery, siteFilters, currentYearInjected };
}

async function runSearchPlan(
  plan: SearchPlanItem[],
  settings: SearchSettings,
  signal?: AbortSignal,
): Promise<{ results: SearchResult[]; warnings: SearchWarning[] }> {
  const results: SearchResult[] = [];
  const warnings: SearchWarning[] = [];

  for (let index = 0; index < plan.length; index += MAX_CONCURRENCY) {
    const batch = plan.slice(index, index + MAX_CONCURRENCY);
    const settled = await Promise.all(
      batch.map(async (item) => {
        try {
          const result = await runWebSearchPass(item, settings, signal);
          return { ok: true as const, result };
        } catch (error) {
          return { ok: false as const, warning: { ...item, error: errorToMessage(error) } };
        }
      }),
    );

    for (const item of settled) {
      if (item.ok) results.push(item.result);
      else warnings.push(item.warning);
    }
  }

  return { results, warnings };
}

async function runWebSearchPass(item: SearchPlanItem, settings: SearchSettings, signal?: AbortSignal): Promise<SearchResult> {
  const event = await callExaMcpWithRetries(
    "web_search_exa",
    {
      query: item.query,
      type: settings.depth,
      numResults: settings.results,
      livecrawl: settings.livecrawl,
      contextMaxCharacters: settings.maxCharacters,
    },
    30_000,
    signal,
  );

  return {
    ...item,
    urls: extractUrlsFromMcpResult(event?.result),
  };
}

async function callExaMcpWithRetries(
  toolName: string,
  args: Record<string, unknown>,
  timeoutMs: number,
  signal?: AbortSignal,
): Promise<any> {
  let lastError: unknown;

  for (let attempt = 0; attempt <= EXA_RETRIES; attempt++) {
    if (signal?.aborted) throw new Error("Search cancelled.");

    try {
      return await callExaMcpOnce(toolName, args, timeoutMs, signal);
    } catch (error) {
      lastError = error;
      if (signal?.aborted || attempt >= EXA_RETRIES) break;
      await sleep(EXA_RETRY_DELAY_MS, signal);
    }
  }

  throw lastError instanceof Error ? lastError : new Error(String(lastError));
}

async function callExaMcpOnce(
  toolName: string,
  args: Record<string, unknown>,
  timeoutMs: number,
  signal?: AbortSignal,
): Promise<any> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(new Error(`Exa MCP request timed out after ${timeoutMs}ms.`)), timeoutMs);
  const abortFromParent = () => controller.abort(signal?.reason ?? new Error("Search cancelled."));

  if (signal?.aborted) abortFromParent();
  else signal?.addEventListener("abort", abortFromParent, { once: true });

  try {
    const response = await fetch(EXA_MCP_URL, {
      method: "POST",
      headers: {
        accept: "application/json, text/event-stream",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: { name: toolName, arguments: args },
      }),
      signal: controller.signal,
    });

    const raw = await response.text();
    if (!response.ok) {
      throw new Error(`Exa MCP request failed with HTTP ${response.status}: ${normalizeWhitespace(raw)}`);
    }

    return extractMcpResultEvent(raw);
  } catch (error) {
    if (signal?.aborted) throw new Error("Search cancelled.");
    throw error;
  } finally {
    clearTimeout(timeout);
    signal?.removeEventListener("abort", abortFromParent);
  }
}

function extractMcpResultEvent(raw: string): any {
  const events: any[] = [];

  for (const rawLine of raw.split(/\r?\n/)) {
    const line = rawLine.replace(/\r$/, "");
    if (!line.startsWith("data:")) continue;

    const jsonText = line.slice("data:".length).trimStart();
    if (!jsonText) continue;

    try {
      events.push(JSON.parse(jsonText));
    } catch {
      // Ignore non-JSON SSE data lines.
    }
  }

  if (events.length === 0) {
    try {
      events.push(JSON.parse(raw));
    } catch {
      throw new Error("Exa MCP response did not include valid SSE data events.");
    }
  }

  const errorEvent = [...events].reverse().find((event) => event?.error != null);
  if (errorEvent) {
    const code = errorEvent.error?.code == null ? "" : ` (${errorEvent.error.code})`;
    const message = errorEvent.error?.message ?? "Unknown Exa MCP error";
    throw new Error(`Exa MCP error${code}: ${message}`);
  }

  const resultEvent = [...events].reverse().find((event) => event?.result?.content?.[0] != null);
  if (!resultEvent) {
    throw new Error("Exa MCP response did not include a usable result.");
  }

  return resultEvent;
}

function renderMarkdownToolResult(
  result: { content?: Array<{ type?: string; text?: string }> },
  options: { isPartial: boolean },
  partialText: string,
  emptyText: string,
) {
  const contentText = getTextContent(result);
  const text = contentText || (options.isPartial ? partialText : emptyText);
  const markdown = options.isPartial && !contentText ? `_${text}_` : text;
  return new Markdown(markdown, 0, 0, getMarkdownTheme());
}

function getTextContent(result: { content?: Array<{ type?: string; text?: string }> }): string {
  return result.content?.find((item) => item.type === "text" && typeof item.text === "string")?.text?.trim() ?? "";
}

function normalizeTopicQuery(query: string): string {
  return query.replace(/(^|\s)site:\S+/g, " ").replace(/\s+/g, " ").trim();
}

function extractSiteFilters(query: string): string[] {
  return Array.from(query.matchAll(/site:\S+/g), (match) => match[0]);
}

function hasGithubConstraint(query: string): boolean {
  return /(^|\s)site:github\.com(\s|$)|(^|\s)github\.com(\s|\/|$)|(^|\s)github(\s|$)/i.test(query);
}

function hasYearToken(query: string): boolean {
  return /(^|[^0-9])(19|20)[0-9]{2}([^0-9]|$)/.test(query);
}

function appendRecentYearIfNeeded(query: string): string {
  return hasYearToken(query) ? query : `${query} ${new Date().getFullYear()}`;
}

function isRecencySensitive(query: string): boolean {
  return /(^|\s)(latest|recent|new|update|updates|release|releases|announcement|announcements|changelog|today|this year|current|now|20[0-9]{2})(\s|$)/i.test(
    query,
  );
}

function normalizeWhitespace(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

function errorToMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function readPositiveIntEnv(names: string | string[], fallback: number): number {
  for (const name of Array.isArray(names) ? names : [names]) {
    const value = process.env[name];
    if (!value) continue;

    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed) && parsed >= 0) return parsed;
  }

  return fallback;
}

function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new Error("Search cancelled."));
      return;
    }

    const abort = () => {
      clearTimeout(timeout);
      reject(new Error("Search cancelled."));
    };
    const timeout = setTimeout(() => {
      signal?.removeEventListener("abort", abort);
      resolve();
    }, ms);

    signal?.addEventListener("abort", abort, { once: true });
  });
}
