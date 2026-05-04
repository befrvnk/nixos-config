export interface WebSearchFormatInput {
  originalQuery: string;
  mode: string;
  focus: string;
  settings: {
    results: number;
    depth: string;
    freshness: string;
    maxCharacters: number;
  };
  plan: Array<{ label: string; query: string }>;
  results: Array<{ label: string; query: string; searchTime: unknown; text: string }>;
  warnings: Array<{ label: string; query: string; error: string }>;
  currentYearInjected: boolean;
}

export function formatWebSearchOutput(input: WebSearchFormatInput): string {
  const totalSearchTime = input.results.reduce((sum, result) => {
    return typeof result.searchTime === "number" ? sum + result.searchTime : sum;
  }, 0);

  const lines: string[] = [];
  lines.push(input.mode === "single" ? "# Web search" : "# Web research overview");
  lines.push("");
  lines.push(`**Query:** ${input.originalQuery}`);
  lines.push(`**Mode:** ${inlineCode(input.mode)}`);
  lines.push(`**Focus:** ${inlineCode(input.focus)}`);
  lines.push(
    `**Per-search settings:** results=${input.settings.results}, depth=${inlineCode(input.settings.depth)}, freshness=${inlineCode(input.settings.freshness)}, maxCharacters=${input.settings.maxCharacters}`,
  );
  if (totalSearchTime > 0) lines.push(`**Combined search time:** ${Math.round(totalSearchTime * 10) / 10}ms`);
  if (input.currentYearInjected) lines.push(`**Recent-pass year hint:** ${new Date().getFullYear()}`);

  lines.push("");
  lines.push("## Search plan");
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

  for (const result of input.results) {
    lines.push("");
    lines.push(`## ${result.label}`);
    lines.push("");
    lines.push(`**Query:** ${inlineCode(result.query)}`);
    if (result.searchTime != null) lines.push(`**Search time:** ${result.searchTime}ms`);
    lines.push("");
    lines.push(result.text?.trim() || "No results found.");
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
