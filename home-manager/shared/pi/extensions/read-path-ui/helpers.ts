import { isAbsolute, relative, resolve, sep } from "node:path";

export const ARROW = "⎿";

export type ReadRenderArgs = {
  file_path?: unknown;
  path?: unknown;
  offset?: unknown;
  limit?: unknown;
};

export type ToolSummaryColor = "accent" | "dim" | "error" | "muted" | "success" | "toolTitle";
export type ToolSummaryBgColor = "toolErrorBg" | "toolPendingBg" | "toolSuccessBg";
export type ToolSummaryStatus = "loading" | "success" | "failed";

export type ThemeLike = {
  bold(text: string): string;
  fg(color: ToolSummaryColor, text: string): string;
  bg?: (color: ToolSummaryBgColor, text: string) => string;
};

export type TextContentLike = {
  type?: unknown;
  text?: unknown;
};

export type ToolSummaryData = {
  id: string;
  kind: string;
  title: string;
  countSingular: string;
  countPlural: string;
  item: string;
  status: ToolSummaryStatus;
  loadingLabel: string;
  failedLabel: string;
  errorLine?: string;
  expanded: boolean;
  theme: ThemeLike;
};

export function stringArg(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

export function numberArg(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

export function readPath(args: ReadRenderArgs | undefined): string | undefined {
  return stringArg(args?.file_path) ?? stringArg(args?.path);
}

export function stripAtPrefix(path: string): string {
  return path.startsWith("@") ? path.slice(1) : path;
}

export function toPosixPath(path: string): string {
  return path.split(sep).join("/");
}

export function formatDisplayPath(rawPath: string | undefined, cwd: string): string {
  if (!rawPath) return "unknown file";

  const withoutAt = stripAtPrefix(rawPath);
  if (!withoutAt) return "unknown file";

  const absolutePath = isAbsolute(withoutAt) ? withoutAt : resolve(cwd, withoutAt);
  const relativePath = relative(cwd, absolutePath);
  if (relativePath && !relativePath.startsWith("..") && !isAbsolute(relativePath)) {
    return toPosixPath(relativePath);
  }

  return toPosixPath(withoutAt);
}

export function formatLineRange(args: ReadRenderArgs | undefined): string {
  const offset = numberArg(args?.offset);
  const limit = numberArg(args?.limit);
  if (offset === undefined && limit === undefined) return "";

  const startLine = offset ?? 1;
  if (limit === undefined) return `:${startLine}`;

  const endLine = Math.max(startLine, startLine + limit - 1);
  return `:${startLine}-${endLine}`;
}

export function getResultText(result: { content?: unknown }): string | undefined {
  if (!Array.isArray(result.content)) return undefined;

  return result.content
    .map((item: TextContentLike) => (item?.type === "text" && typeof item.text === "string" ? item.text : undefined))
    .filter((text): text is string => Boolean(text))
    .join("\n");
}

export function firstNonEmptyLine(text: string | undefined): string | undefined {
  return text
    ?.split("\n")
    .map((line) => line.trim())
    .find(Boolean);
}

export function countLabel(count: number, summary: ToolSummaryData): string {
  return `${count} ${count === 1 ? summary.countSingular : summary.countPlural}`;
}

export function summaryHeader(count: number, summary: ToolSummaryData): string {
  return `${summary.theme.fg("toolTitle", summary.theme.bold(summary.title))} ${summary.theme.fg("accent", countLabel(count, summary))}`;
}

export function summaryLine(summary: ToolSummaryData): string {
  if (summary.status === "loading") {
    return `${summary.theme.fg("muted", ARROW)}  ${summary.theme.fg("muted", summary.loadingLabel)} ${summary.theme.fg("accent", summary.item)}`;
  }

  if (summary.status === "failed") {
    return `${summary.theme.fg("error", ARROW)}  ${summary.theme.fg("error", summary.failedLabel)} ${summary.theme.fg("accent", summary.item)}`;
  }

  return `${summary.theme.fg("success", ARROW)}  ${summary.theme.fg("accent", summary.item)}`;
}

export function backgroundColorForGroup(group: ToolSummaryData[]): ToolSummaryBgColor {
  if (group.some((summary) => summary.status === "failed")) return "toolErrorBg";
  if (group.some((summary) => summary.status === "loading")) return "toolPendingBg";
  return "toolSuccessBg";
}

export function readSummaryData(params: {
  id: string;
  args: ReadRenderArgs | undefined;
  cwd: string;
  status: ToolSummaryStatus;
  errorLine?: string;
  expanded: boolean;
  theme: ThemeLike;
}): ToolSummaryData {
  return {
    id: params.id,
    kind: "read",
    title: "Read",
    countSingular: "file",
    countPlural: "files",
    item: `${formatDisplayPath(readPath(params.args), params.cwd)}${formatLineRange(params.args)}`,
    status: params.status,
    loadingLabel: "Loading",
    failedLabel: "Failed to load",
    errorLine: params.errorLine,
    expanded: params.expanded,
    theme: params.theme,
  };
}
