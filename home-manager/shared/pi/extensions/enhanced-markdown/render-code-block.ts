type MarkdownToken = {
  lang?: string;
  text?: string;
};

type CodeBlockTheme = {
  codeBlock: (text: string) => string;
  codeBlockBorder: (text: string) => string;
  highlightCode?: (code: string, lang?: string) => string[];
};

type RenderUtilities = {
  truncateToWidth: (text: string, width: number, ellipsis?: string) => string;
  visibleWidth: (text: string) => number;
  wrapTextWithAnsi: (text: string, width: number) => string[];
};

const LANGUAGE_ALIASES: Record<string, string | undefined> = {
  cjs: "javascript",
  console: "bash",
  js: "javascript",
  jsx: "javascript",
  kts: "kotlin",
  kt: "kotlin",
  markdown: "markdown",
  md: "markdown",
  mjs: "javascript",
  none: undefined,
  plain: undefined,
  plaintext: undefined,
  ps1: "powershell",
  shell: "bash",
  sh: "bash",
  text: undefined,
  ts: "typescript",
  tsx: "typescript",
  txt: undefined,
  yml: "yaml",
  zsh: "bash",
};

export function normalizeLanguage(lang: string | undefined): string | undefined {
  const normalized = lang?.trim().split(/\s+/, 1)[0]?.toLowerCase();
  if (!normalized) return undefined;
  return Object.prototype.hasOwnProperty.call(LANGUAGE_ALIASES, normalized)
    ? LANGUAGE_ALIASES[normalized]
    : normalized;
}

function displayLanguage(lang: string | undefined): string {
  const normalized = lang?.trim();
  return normalized ? normalized : "code";
}

function borderedLine(
  text: string,
  width: number,
  border: (value: string) => string,
  utilities: RenderUtilities,
): string {
  if (width <= 0) return "";
  if (width === 1) return border("─");

  const visibleText = utilities.truncateToWidth(text, Math.max(0, width - 5), "…");
  const lineStart = visibleText ? `╭─ ${visibleText} ` : "╭─ ";
  const remaining = Math.max(0, width - utilities.visibleWidth(lineStart) - 1);
  return border(`${lineStart}${"─".repeat(remaining)}╮`);
}

function bottomBorder(width: number, border: (value: string) => string): string {
  if (width <= 0) return "";
  if (width === 1) return border("─");
  return border(`╰${"─".repeat(Math.max(0, width - 2))}╯`);
}

export function renderCodeBlockLines(
  theme: CodeBlockTheme,
  token: MarkdownToken,
  width: number,
  nextTokenType: string | undefined,
  utilities: RenderUtilities,
): string[] {
  const code = token.text ?? "";
  const language = normalizeLanguage(token.lang);
  const border = theme.codeBlockBorder;
  const hasPrefixRoom = width > 2;
  const contentWidth = Math.max(1, width - (hasPrefixRoom ? 2 : 0));
  const prefix = hasPrefixRoom ? border("│ ") : "";

  const highlightedLines = theme.highlightCode
    ? theme.highlightCode(code, language)
    : code.split("\n").map((line) => theme.codeBlock(line));

  const lines: string[] = [
    borderedLine(displayLanguage(token.lang), width, border, utilities),
  ];

  for (const highlightedLine of highlightedLines) {
    const wrapped = utilities.wrapTextWithAnsi(highlightedLine, contentWidth);
    if (wrapped.length === 0) {
      lines.push(prefix);
    } else {
      for (const wrappedLine of wrapped) {
        lines.push(`${prefix}${wrappedLine}`);
      }
    }
  }

  lines.push(bottomBorder(width, border));

  if (nextTokenType && nextTokenType !== "space") {
    lines.push("");
  }

  return lines;
}
