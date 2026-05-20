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

type HighlightCode = (code: string, lang?: string) => string[];

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

function headerSeparator(
  text: string,
  width: number,
  border: (value: string) => string,
  utilities: RenderUtilities,
): string {
  if (width <= 0) return "";
  if (width <= 3) return border("─".repeat(width));

  const visibleText = utilities.truncateToWidth(text, width - 3, "…");
  const lineStart = visibleText ? `─ ${visibleText} ` : "─ ";
  const remaining = Math.max(0, width - utilities.visibleWidth(lineStart));
  return border(`${lineStart}${"─".repeat(remaining)}`);
}

function bottomSeparator(width: number, border: (value: string) => string): string {
  if (width <= 0) return "";
  return border("─".repeat(width));
}

export function renderCodeBlockLines(
  theme: CodeBlockTheme,
  token: MarkdownToken,
  width: number,
  nextTokenType: string | undefined,
  utilities: RenderUtilities,
  highlightCode?: HighlightCode,
): string[] {
  const code = token.text ?? "";
  const language = normalizeLanguage(token.lang);
  const border = theme.codeBlockBorder;
  const contentWidth = Math.max(1, width);

  const highlightedLines = highlightCode
    ? highlightCode(code, language)
    : theme.highlightCode
      ? theme.highlightCode(code, language)
      : code.split("\n").map((line) => theme.codeBlock(line));

  const lines: string[] = [
    headerSeparator(displayLanguage(token.lang), width, border, utilities),
  ];

  for (const highlightedLine of highlightedLines) {
    const wrapped = utilities.wrapTextWithAnsi(highlightedLine, contentWidth);
    if (wrapped.length === 0) {
      lines.push("");
    } else {
      for (const wrappedLine of wrapped) {
        lines.push(wrappedLine);
      }
    }
  }

  lines.push(bottomSeparator(width, border));

  if (nextTokenType && nextTokenType !== "space") {
    lines.push("");
  }

  return lines;
}
