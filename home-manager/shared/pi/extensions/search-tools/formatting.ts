export interface WebSearchFormatInput {
  originalQuery: string;
  plan: Array<{ label: string; query: string }>;
  results: Array<{ label: string; query: string; urls: string[] }>;
  warnings: Array<{ label: string; query: string; error: string }>;
}

export function formatWebSearchOutput(input: WebSearchFormatInput): string {
  const lines: string[] = [];
  lines.push("# Web search sources");
  lines.push("");
  lines.push(`**Query:** ${input.originalQuery}`);

  lines.push("");
  lines.push("## Search queries");
  lines.push("");
  for (const item of input.plan) lines.push(`- **${item.label}:** ${inlineCode(item.query)}`);

  if (input.warnings.length > 0) {
    lines.push("");
    lines.push("## Warnings");
    lines.push("");
    for (const warning of input.warnings) {
      lines.push(`- **${warning.label}** failed for ${inlineCode(warning.query)}: ${warning.error}`);
    }
  }

  lines.push("");
  lines.push("## URLs");

  for (const result of input.results) {
    lines.push("");
    lines.push(`### ${result.label}`);
    lines.push("");
    lines.push(`**Query:** ${inlineCode(result.query)}`);
    lines.push("");

    if (result.urls.length === 0) {
      lines.push("No URLs found.");
    } else {
      for (const url of result.urls) lines.push(`- ${url}`);
    }
  }

  return lines.join("\n");
}

export interface WebFetchFormatInput {
  originalUrl: string;
  finalUrl: string;
  status: number;
  contentType: string;
  format: string;
  title: string | null;
  bytes: number;
  maxCharacters: number;
  truncated: boolean;
  content: string;
  binary: boolean;
}

export function formatWebFetchOutput(input: WebFetchFormatInput): string {
  const lines: string[] = [];
  lines.push("# Web fetch");
  lines.push("");
  lines.push(`**URL:** ${input.originalUrl}`);
  if (input.finalUrl !== input.originalUrl) lines.push(`**Final URL:** ${input.finalUrl}`);
  lines.push(`**Status:** ${input.status}`);
  if (input.contentType) lines.push(`**Content type:** ${input.contentType}`);
  lines.push(`**Format:** ${inlineCode(input.format)}`);
  if (input.title) lines.push(`**Title:** ${input.title}`);
  lines.push(`**Bytes:** ${input.bytes}`);
  if (input.truncated) lines.push(`**Truncated:** yes, limited to ${input.maxCharacters} characters`);
  if (input.binary) lines.push("**Binary:** yes, body omitted");

  lines.push("");
  lines.push("## Content");
  lines.push("");

  const content = input.content.trim() || "No content returned.";
  if (input.format === "html" && !input.binary) {
    lines.push(fencedCode(content, "html"));
  } else {
    lines.push(content);
  }

  return lines.join("\n");
}

export function formatCodeSearchOutput(query: string, maxTokens: number, searchTime: unknown, text: string): string {
  const lines: string[] = [];
  lines.push("# Code search");
  lines.push("");
  lines.push(`**Query:** ${query}`);
  lines.push(`**Max tokens:** ${maxTokens}`);
  if (searchTime != null) lines.push(`**Search time:** ${searchTime}ms`);
  lines.push("");
  lines.push(text?.trim() || "No code snippets or documentation found.");
  return lines.join("\n");
}

function inlineCode(text: string): string {
  const longestBacktickRun = Math.max(0, ...Array.from(text.matchAll(/`+/g), (match) => match[0].length));
  const fence = "`".repeat(longestBacktickRun + 1);
  const padding = text.startsWith("`") || text.endsWith("`") ? " " : "";
  return `${fence}${padding}${text}${padding}${fence}`;
}

function fencedCode(text: string, language: string): string {
  const longestBacktickRun = Math.max(2, ...Array.from(text.matchAll(/`+/g), (match) => match[0].length));
  const fence = "`".repeat(longestBacktickRun + 1);
  return `${fence}${language}\n${text}\n${fence}`;
}
