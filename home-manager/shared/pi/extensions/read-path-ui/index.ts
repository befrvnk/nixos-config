import { createReadTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Box, Container, Text } from "@earendil-works/pi-tui";
import {
  backgroundColorForGroup,
  firstNonEmptyLine,
  getResultText,
  readSummaryData,
  summaryHeader,
  summaryLine,
  type ReadRenderArgs,
  type ThemeLike,
  type ToolSummaryData,
} from "./helpers.ts";

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

function renderSummaryGroup(group: ToolSummaryData[], width: number): string[] {
  const latest = group[group.length - 1];
  if (!latest) return [];

  const expanded = group.some((summary) => summary.expanded);
  const bgColor = backgroundColorForGroup(group);
  const box = new Box(1, 1, (line: string) => (latest.theme.bg ? latest.theme.bg(bgColor, line) : line));

  box.addChild(new Text(summaryHeader(group.length, latest), 0, 0));
  for (const summary of group) {
    box.addChild(new Text(summaryLine(summary), 0, 0));
    if (expanded && summary.status === "failed" && summary.errorLine) {
      box.addChild(new Text(summary.theme.fg("dim", `   ${summary.errorLine}`), 0, 0));
    }
  }

  return ["", ...box.render(width)];
}

type ContainerRender = (width: number) => string[];

function renderWithGroupedSummaries(
  container: Container & { children: unknown[] },
  width: number,
  original: ContainerRender,
): string[] {
  const children = container.children;
  if (!Array.isArray(children)) return original.call(container, width);

  const lines: string[] = [];

  for (let index = 0; index < children.length; index++) {
    const child = children[index] as { render: ContainerRender };
    const first = getGroupedSummaryData(child);
    if (!first) {
      lines.push(...child.render(width));
      continue;
    }

    const group: ToolSummaryData[] = [];
    let cursor = index;
    while (cursor < children.length) {
      const summary = getGroupedSummaryData(children[cursor]);
      if (!summary || summary.kind !== first.kind) break;
      group.push(summary);
      cursor++;
    }

    lines.push(...renderSummaryGroup(group, width));
    index = cursor - 1;
  }

  return lines;
}

function patchContainerRender() {
  const prototype = Container.prototype as typeof Container.prototype & {
    [CONTAINER_PATCH_MARKER]?: boolean;
    [ORIGINAL_CONTAINER_RENDER]?: ContainerRender;
  };

  if (prototype[CONTAINER_PATCH_MARKER]) return;

  const original = prototype.render as ContainerRender;
  prototype[ORIGINAL_CONTAINER_RENDER] = original;
  prototype.render = function patchedContainerRender(width: number): string[] {
    // The grouping logic reads pi-tui component internals (children, render).
    // If an upstream change breaks those assumptions, fall back to the original
    // renderer instead of throwing on every frame.
    try {
      return renderWithGroupedSummaries(this as Container & { children: unknown[] }, width, original);
    } catch {
      return original.call(this, width);
    }
  };
  prototype[CONTAINER_PATCH_MARKER] = true;
}

function updateSummaryData(next: ToolSummaryData) {
  const summaries = getSummaries();
  const previous = summaries.get(next.id);
  summaries.set(next.id, previous ? { ...previous, ...next } : next);
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
        component.setText(summaryHeader(1, data));
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
