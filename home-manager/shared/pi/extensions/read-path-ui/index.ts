import { createReadTool, type ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Box, Container, Text } from "@mariozechner/pi-tui";
import { isAbsolute, relative, resolve, sep } from "node:path";

type ReadRenderArgs = {
  file_path?: unknown;
  path?: unknown;
  offset?: unknown;
  limit?: unknown;
};

type ToolSummaryColor = "accent" | "dim" | "error" | "muted" | "success" | "toolTitle";
type ToolSummaryBgColor = "toolErrorBg" | "toolPendingBg" | "toolSuccessBg";
type ToolSummaryStatus = "loading" | "success" | "failed";

type ThemeLike = {
  bold(text: string): string;
  fg(color: ToolSummaryColor, text: string): string;
  bg?: (color: ToolSummaryBgColor, text: string) => string;
};

type TextContentLike = {
  type?: unknown;
  text?: unknown;
};

type ToolSummaryData = {
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

const ARROW = "⎿";
const SUMMARY_MARKER = Symbol.for("frank.pi.tool-summary-ui.marker");
const CONTAINER_PATCH_MARKER = Symbol.for("frank.pi.tool-summary-ui.container-patch-v1");
const ORIGINAL_CONTAINER_RENDER = Symbol.for("frank.pi.tool-summary-ui.original-container-render");
const STATE = Symbol.for("frank.pi.tool-summary-ui.state");

type ToolSummaryState = {
  summaries: Map<string, ToolSummaryData>;
};

function getState(): ToolSummaryState {
  const globalState = globalThis as typeof globalThis & { [STATE]?: ToolSummaryState };
  globalState[STATE] ??= { summaries: new Map<string, ToolSummaryData>() };
  return globalState[STATE];
}

function getSummaries(): Map<string, ToolSummaryData> {
  return getState().summaries;
}

class ToolSummaryText extends Text {
  [SUMMARY_MARKER] = true;

  constructor(
    public readonly summaryId: string,
    text: string,
  ) {
    super(text, 0, 0);
  }
}

function toToolSummaryText(component: unknown, id: string): ToolSummaryText {
  return component instanceof ToolSummaryText && component.summaryId === id ? component : new ToolSummaryText(id, "");
}

function stringArg(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function numberArg(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function readPath(args: ReadRenderArgs | undefined): string | undefined {
  return stringArg(args?.file_path) ?? stringArg(args?.path);
}

function stripAtPrefix(path: string): string {
  return path.startsWith("@") ? path.slice(1) : path;
}

function toPosixPath(path: string): string {
  return path.split(sep).join("/");
}

function formatDisplayPath(rawPath: string | undefined, cwd: string): string {
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

function formatLineRange(args: ReadRenderArgs | undefined): string {
  const offset = numberArg(args?.offset);
  const limit = numberArg(args?.limit);
  if (offset === undefined && limit === undefined) return "";

  const startLine = offset ?? 1;
  if (limit === undefined) return `:${startLine}`;

  const endLine = Math.max(startLine, startLine + limit - 1);
  return `:${startLine}-${endLine}`;
}

function getResultText(result: { content?: unknown }): string | undefined {
  if (!Array.isArray(result.content)) return undefined;

  return result.content
    .map((item: TextContentLike) => (item?.type === "text" && typeof item.text === "string" ? item.text : undefined))
    .filter((text): text is string => Boolean(text))
    .join("\n");
}

function firstNonEmptyLine(text: string | undefined): string | undefined {
  return text
    ?.split("\n")
    .map((line) => line.trim())
    .find(Boolean);
}

function countLabel(count: number, summary: ToolSummaryData): string {
  return `${count} ${count === 1 ? summary.countSingular : summary.countPlural}`;
}

function summaryHeader(count: number, _expanded: boolean, summary: ToolSummaryData): string {
  return `${summary.theme.fg("toolTitle", summary.theme.bold(summary.title))} ${summary.theme.fg("accent", countLabel(count, summary))}`;
}

function summaryLine(summary: ToolSummaryData): string {
  if (summary.status === "loading") {
    return `${summary.theme.fg("muted", ARROW)}  ${summary.theme.fg("muted", summary.loadingLabel)} ${summary.theme.fg("accent", summary.item)}`;
  }

  if (summary.status === "failed") {
    return `${summary.theme.fg("error", ARROW)}  ${summary.theme.fg("error", summary.failedLabel)} ${summary.theme.fg("accent", summary.item)}`;
  }

  return `${summary.theme.fg("success", ARROW)}  ${summary.theme.fg("accent", summary.item)}`;
}

function hasSummaryMarker(component: unknown): component is { [SUMMARY_MARKER]: true; summaryId: string } {
  return Boolean(
    component &&
      typeof component === "object" &&
      (component as { [SUMMARY_MARKER]?: unknown })[SUMMARY_MARKER] === true &&
      typeof (component as { summaryId?: unknown }).summaryId === "string",
  );
}

function findSummaryId(component: unknown, visited = new Set<unknown>()): string | undefined {
  if (!component || typeof component !== "object" || visited.has(component)) return undefined;
  visited.add(component);

  if (hasSummaryMarker(component)) return component.summaryId;

  const children = (component as { children?: unknown }).children;
  if (!Array.isArray(children)) return undefined;

  for (const child of children) {
    const id = findSummaryId(child, visited);
    if (id) return id;
  }

  return undefined;
}

function getGroupedSummaryData(component: unknown): ToolSummaryData | undefined {
  if (!component || typeof component !== "object") return undefined;
  if (typeof (component as { setExpanded?: unknown }).setExpanded !== "function") return undefined;

  const id = findSummaryId(component);
  return id ? getSummaries().get(id) : undefined;
}

function backgroundColorForGroup(group: ToolSummaryData[]): ToolSummaryBgColor {
  if (group.some((summary) => summary.status === "failed")) return "toolErrorBg";
  if (group.some((summary) => summary.status === "loading")) return "toolPendingBg";
  return "toolSuccessBg";
}

function renderSummaryGroup(group: ToolSummaryData[], width: number): string[] {
  const latest = group[group.length - 1];
  if (!latest) return [];

  const expanded = group.some((summary) => summary.expanded);
  const bgColor = backgroundColorForGroup(group);
  const box = new Box(1, 1, (line: string) => (latest.theme.bg ? latest.theme.bg(bgColor, line) : line));

  box.addChild(new Text(summaryHeader(group.length, expanded, latest), 0, 0));
  for (const summary of group) {
    box.addChild(new Text(summaryLine(summary), 0, 0));
    if (expanded && summary.status === "failed" && summary.errorLine) {
      box.addChild(new Text(summary.theme.fg("dim", `   ${summary.errorLine}`), 0, 0));
    }
  }

  return ["", ...box.render(width)];
}

function patchContainerRender() {
  const prototype = Container.prototype as typeof Container.prototype & {
    [CONTAINER_PATCH_MARKER]?: boolean;
    [ORIGINAL_CONTAINER_RENDER]?: (width: number) => string[];
  };

  if (prototype[CONTAINER_PATCH_MARKER]) return;

  prototype[ORIGINAL_CONTAINER_RENDER] = prototype.render;
  prototype.render = function renderWithGroupedToolSummaries(width: number): string[] {
    const lines: string[] = [];

    for (let index = 0; index < this.children.length; index++) {
      const first = getGroupedSummaryData(this.children[index]);
      if (!first) {
        lines.push(...this.children[index]!.render(width));
        continue;
      }

      const group: ToolSummaryData[] = [];
      let cursor = index;
      while (cursor < this.children.length) {
        const summary = getGroupedSummaryData(this.children[cursor]);
        if (!summary || summary.kind !== first.kind) break;
        group.push(summary);
        cursor++;
      }

      lines.push(...renderSummaryGroup(group, width));
      index = cursor - 1;
    }

    return lines;
  };
  prototype[CONTAINER_PATCH_MARKER] = true;
}

function updateSummaryData(next: ToolSummaryData) {
  const summaries = getSummaries();
  const previous = summaries.get(next.id);
  summaries.set(next.id, previous ? { ...previous, ...next } : next);
}

function readSummaryData(params: {
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

export default function readPathUiExtension(pi: ExtensionAPI) {
  patchContainerRender();

  pi.on("session_start", (_event, ctx) => {
    getSummaries().clear();
    const builtinRead = createReadTool(ctx.cwd);

    pi.registerTool({
      ...builtinRead,
      label: "Read",

      renderCall(args: ReadRenderArgs | undefined, theme: ThemeLike, context) {
        const summaryId = context.toolCallId;
        const component = toToolSummaryText(context.lastComponent, summaryId);
        const current = getSummaries().get(summaryId);
        const data = readSummaryData({
          id: summaryId,
          args,
          cwd: context.cwd,
          status: current?.status ?? "loading",
          errorLine: current?.errorLine,
          expanded: context.expanded,
          theme,
        });
        updateSummaryData(data);
        component.setText(summaryHeader(1, context.expanded, data));
        return component;
      },

      renderResult(result, options, theme: ThemeLike, context) {
        const summaryId = context.toolCallId;
        const component = toToolSummaryText(context.lastComponent, summaryId);
        const args = context.args as ReadRenderArgs | undefined;
        const current = getSummaries().get(summaryId);
        const data = readSummaryData({
          id: summaryId,
          args,
          cwd: context.cwd,
          status: options.isPartial ? "loading" : context.isError ? "failed" : "success",
          errorLine: context.isError ? firstNonEmptyLine(getResultText(result)) : current?.errorLine,
          expanded: context.expanded,
          theme,
        });
        updateSummaryData(data);

        let output = summaryLine(data);
        if (options.expanded && data.status === "failed" && data.errorLine) {
          output += `\n   ${theme.fg("dim", data.errorLine)}`;
        }
        component.setText(output);
        return component;
      },
    });
  });
}
