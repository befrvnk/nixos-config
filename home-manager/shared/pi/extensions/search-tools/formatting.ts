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
