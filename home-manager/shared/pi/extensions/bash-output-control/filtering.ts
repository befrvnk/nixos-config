export type BashOutputFilterMode = "regex" | "literal";

export type BashOutputViewOptions = {
  include?: string[];
  exclude?: string[];
  filterMode?: BashOutputFilterMode;
  ignoreCase?: boolean;
  tailLines?: number;
  maxBytes?: number;
};

export type BashOutputViewStats = {
  totalLines: number;
  matchedLines: number;
  displayedLines: number;
  omittedMatchingLines: number;
  outputBytes: number;
  displayedBytes: number;
  truncatedByBytes: boolean;
  hasFilters: boolean;
};

export type BashOutputView = {
  text: string;
  stats: BashOutputViewStats;
};

export const DEFAULT_BASH_TAIL_LINES = 2_000;
export const DEFAULT_BASH_MAX_BYTES = 50 * 1024;
export const MAX_BASH_TAIL_LINES = 20_000;
export const MAX_BASH_MAX_BYTES = 1024 * 1024;

function clampInteger(value: unknown, fallback: number, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.min(max, Math.max(min, Math.floor(value)));
}

function escapeRegExp(pattern: string): string {
  return pattern.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function compilePatterns(
  patterns: string[] | undefined,
  mode: BashOutputFilterMode,
  ignoreCase: boolean,
): RegExp[] {
  return (patterns ?? [])
    .filter((pattern) => pattern.length > 0)
    .map((pattern) => new RegExp(mode === "literal" ? escapeRegExp(pattern) : pattern, ignoreCase ? "i" : ""));
}

function utf8Bytes(text: string): number {
  return Buffer.byteLength(text, "utf8");
}

function trimToLastBytes(text: string, maxBytes: number): { text: string; truncated: boolean } {
  if (maxBytes <= 0) return { text: "", truncated: text.length > 0 };

  const buffer = Buffer.from(text, "utf8");
  if (buffer.length <= maxBytes) return { text, truncated: false };

  let trimmed = buffer.subarray(buffer.length - maxBytes).toString("utf8");

  // Avoid starting with replacement characters after slicing through a multi-byte codepoint.
  while (trimmed.startsWith("\uFFFD")) trimmed = trimmed.slice(1);

  return { text: trimmed, truncated: true };
}

export function normalizeBashOutputViewOptions(options: BashOutputViewOptions): Required<BashOutputViewOptions> {
  return {
    include: options.include ?? [],
    exclude: options.exclude ?? [],
    filterMode: options.filterMode ?? "regex",
    ignoreCase: options.ignoreCase ?? false,
    tailLines: clampInteger(options.tailLines, DEFAULT_BASH_TAIL_LINES, 0, MAX_BASH_TAIL_LINES),
    maxBytes: clampInteger(options.maxBytes, DEFAULT_BASH_MAX_BYTES, 0, MAX_BASH_MAX_BYTES),
  };
}

function normalizeLines(text: string): string {
  return text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
}

function lineMatches(line: string, include: RegExp[], exclude: RegExp[]): boolean {
  if (include.length > 0 && !include.some((pattern) => pattern.test(line))) return false;
  return !exclude.some((pattern) => pattern.test(line));
}

function buildViewFromSelected(params: {
  selectedLines: string[];
  totalLines: number;
  matchedLines: number;
  outputBytes: number;
  hasFilters: boolean;
  maxBytes: number;
}): BashOutputView {
  const tailedText = params.selectedLines.join("\n");
  const byteTrimmed = trimToLastBytes(tailedText, params.maxBytes);
  const displayedText = byteTrimmed.text;
  const displayedLines = displayedText.length === 0 ? 0 : displayedText.split("\n").length;

  return {
    text: displayedText,
    stats: {
      totalLines: params.totalLines,
      matchedLines: params.matchedLines,
      displayedLines,
      omittedMatchingLines: Math.max(0, params.matchedLines - params.selectedLines.length),
      outputBytes: params.outputBytes,
      displayedBytes: utf8Bytes(displayedText),
      truncatedByBytes: byteTrimmed.truncated,
      hasFilters: params.hasFilters,
    },
  };
}

export function buildBashOutputView(output: string, options: BashOutputViewOptions): BashOutputView {
  const normalized = normalizeBashOutputViewOptions(options);
  const include = compilePatterns(normalized.include, normalized.filterMode, normalized.ignoreCase);
  const exclude = compilePatterns(normalized.exclude, normalized.filterMode, normalized.ignoreCase);
  const hasFilters = include.length > 0 || exclude.length > 0;

  const lines = output.length === 0 ? [] : normalizeLines(output).split("\n");
  if (lines.at(-1) === "") lines.pop();

  const selectedLines: string[] = [];
  let matchedLines = 0;
  for (const line of lines) {
    if (!lineMatches(line, include, exclude)) continue;
    matchedLines += 1;
    if (normalized.tailLines === 0) continue;
    selectedLines.push(line);
    if (selectedLines.length > normalized.tailLines) selectedLines.shift();
  }

  return buildViewFromSelected({
    selectedLines,
    totalLines: lines.length,
    matchedLines,
    outputBytes: utf8Bytes(output),
    hasFilters,
    maxBytes: normalized.maxBytes,
  });
}

export class BashOutputViewAccumulator {
  private readonly include: RegExp[];
  private readonly exclude: RegExp[];
  private readonly hasFilters: boolean;
  private readonly tailLines: number;
  private readonly maxBytes: number;
  private readonly selectedLines: string[] = [];
  private pending = "";
  private totalLines = 0;
  private matchedLines = 0;
  private outputBytes = 0;
  private finished = false;

  constructor(options: BashOutputViewOptions) {
    const normalized = normalizeBashOutputViewOptions(options);
    this.include = compilePatterns(normalized.include, normalized.filterMode, normalized.ignoreCase);
    this.exclude = compilePatterns(normalized.exclude, normalized.filterMode, normalized.ignoreCase);
    this.hasFilters = this.include.length > 0 || this.exclude.length > 0;
    this.tailLines = normalized.tailLines;
    this.maxBytes = normalized.maxBytes;
  }

  append(text: string): void {
    if (this.finished) throw new Error("Cannot append to a finished BashOutputViewAccumulator");
    this.outputBytes += utf8Bytes(text);
    this.appendText(text);
  }

  finish(): BashOutputView {
    if (!this.finished) {
      if (this.pending.length > 0) {
        const finalLines = normalizeLines(this.pending).split("\n");
        if (finalLines.at(-1) === "") finalLines.pop();
        for (const line of finalLines) this.processLine(line);
        this.pending = "";
      }
      this.finished = true;
    }
    return this.view();
  }

  view(): BashOutputView {
    return buildViewFromSelected({
      selectedLines: this.selectedLines,
      totalLines: this.totalLines,
      matchedLines: this.matchedLines,
      outputBytes: this.outputBytes,
      hasFilters: this.hasFilters,
      maxBytes: this.maxBytes,
    });
  }

  private appendText(text: string): void {
    if (!text) return;

    const combined = this.pending + text;
    const deferTrailingCarriageReturn = combined.endsWith("\r");
    const processable = deferTrailingCarriageReturn ? combined.slice(0, -1) : combined;
    const parts = normalizeLines(processable).split("\n");

    this.pending = parts.pop() ?? "";
    if (deferTrailingCarriageReturn) this.pending += "\r";

    for (const line of parts) this.processLine(line);
  }

  private processLine(line: string): void {
    this.totalLines += 1;
    if (!lineMatches(line, this.include, this.exclude)) return;

    this.matchedLines += 1;
    if (this.tailLines === 0) return;

    this.selectedLines.push(line);
    if (this.selectedLines.length > this.tailLines) this.selectedLines.shift();
  }
}

export function summarizeFilters(options: BashOutputViewOptions): string | undefined {
  const normalized = normalizeBashOutputViewOptions(options);
  const parts: string[] = [];

  if (normalized.include.length > 0) {
    parts.push(`include=${normalized.include.map((pattern) => JSON.stringify(pattern)).join(",")}`);
  }
  if (normalized.exclude.length > 0) {
    parts.push(`exclude=${normalized.exclude.map((pattern) => JSON.stringify(pattern)).join(",")}`);
  }
  if (normalized.include.length > 0 || normalized.exclude.length > 0) {
    parts.push(`mode=${normalized.filterMode}`);
    if (normalized.ignoreCase) parts.push("ignoreCase=true");
  }

  return parts.length > 0 ? parts.join("; ") : undefined;
}

export function formatByteSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  let unit = units[0];
  for (let i = 1; i < units.length && value >= 1024; i += 1) {
    value /= 1024;
    unit = units[i];
  }
  return `${value >= 10 ? value.toFixed(0) : value.toFixed(1)}${unit}`;
}
