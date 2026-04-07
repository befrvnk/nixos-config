import { Text, truncateToWidth } from "@mariozechner/pi-tui";
import { formatDuration } from "./formatting.js";
import type {
  ExploreRunState,
  ExploreTaskResult,
  ExploreTaskState,
} from "./types.js";

const MAX_WIDGET_LINES = 12;
const FINISHED_LINGER_MS = 6_000;
const ERROR_LINGER_MS = 12_000;

export const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

export type Theme = {
  fg(color: string, text: string): string;
  bold(text: string): string;
};

export type UICtx = {
  setStatus(key: string, text: string | undefined): void;
  setWidget(
    key: string,
    content:
      | undefined
      | ((
          tui: any,
          theme: Theme,
        ) => { render(): string[]; invalidate(): void }),
    options?: { placement?: "aboveEditor" | "belowEditor" },
  ): void;
  theme: Theme;
};

function formatTokens(count: number): string {
  if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}M token`;
  if (count >= 1_000) return `${(count / 1_000).toFixed(1)}k token`;
  return `${count} token`;
}

function formatTurns(turnCount: number): string {
  return `⟳${Math.max(1, turnCount)}`;
}

function truncateLine(text: string, len = 64): string {
  const line =
    text
      .split("\n")
      .find((item) => item.trim())
      ?.trim() ?? "";
  if (line.length <= len) return line;
  return `${line.slice(0, len)}…`;
}

function taskLabel(task: ExploreTaskState | ExploreTaskResult): string {
  return truncateLine(task.task, 42) || "Explore task";
}

function describeActivity(task: ExploreTaskState): string {
  const currentTool = task.currentTool?.trim();
  if (currentTool) {
    if (currentTool.startsWith("$ ")) return "running command…";
    if (currentTool.startsWith("read ")) return "reading…";
    if (currentTool.startsWith("grep ")) return "searching…";
    if (currentTool.startsWith("find ")) return "finding files…";
    if (currentTool.startsWith("ls ")) return "listing…";
    return `${currentTool}…`;
  }

  const responsePreview = truncateLine(task.responseText, 72);
  if (responsePreview) return responsePreview;

  const lastOutput = truncateLine(
    task.recentOutputLines[task.recentOutputLines.length - 1] ?? "",
    72,
  );
  if (lastOutput) return lastOutput;

  return "thinking…";
}

function isErrorState(state: string): boolean {
  return state === "error" || state === "aborted";
}

function shouldShowFinishedTask(task: ExploreTaskState): boolean {
  if (
    !task.endedAt ||
    (task.state !== "success" &&
      task.state !== "error" &&
      task.state !== "aborted")
  )
    return false;
  const lingerMs = isErrorState(task.state)
    ? ERROR_LINGER_MS
    : FINISHED_LINGER_MS;
  return Date.now() - task.endedAt < lingerMs;
}

function renderFinishedLine(task: ExploreTaskState, theme: Theme): string {
  const duration = task.startedAt
    ? formatDuration(task.startedAt, task.endedAt)
    : "";
  let icon = theme.fg("success", "✓");
  let statusText = "";

  if (task.state === "error") {
    icon = theme.fg("error", "✗");
    statusText = theme.fg(
      "error",
      ` error${task.error ? `: ${truncateLine(task.error, 48)}` : ""}`,
    );
  } else if (task.state === "aborted") {
    icon = theme.fg("error", "✗");
    statusText = theme.fg("warning", " aborted");
  }

  const parts: string[] = [];
  if (task.turnCount > 0) parts.push(formatTurns(task.turnCount));
  if (task.toolUses > 0)
    parts.push(`${task.toolUses} tool use${task.toolUses === 1 ? "" : "s"}`);
  if (task.tokenCount > 0) parts.push(formatTokens(task.tokenCount));
  if (duration) parts.push(duration);

  return `${icon} ${theme.fg("dim", "Explore")}  ${theme.fg("dim", taskLabel(task))} ${theme.fg("dim", "·")} ${theme.fg("dim", parts.join(" · "))}${statusText}`;
}

function buildWidgetLines(
  runs: ExploreRunState[],
  frame: number,
  theme: Theme,
  width: number,
): string[] {
  const truncate = (line: string) => truncateToWidth(line, width);
  const activeTasks = runs.flatMap((run) =>
    run.tasks.filter((task) => task.state === "running"),
  );
  const pendingTasks = runs.flatMap((run) =>
    run.tasks.filter((task) => task.state === "pending"),
  );
  const finishedTasks = runs.flatMap((run) =>
    run.tasks.filter(shouldShowFinishedTask),
  );
  const hasActive = activeTasks.length > 0 || pendingTasks.length > 0;
  const hasFinished = finishedTasks.length > 0;

  if (!hasActive && !hasFinished) return [];

  const headingColor = hasActive ? "accent" : "dim";
  const headingIcon = hasActive ? "●" : "○";
  const spinner = SPINNER[frame % SPINNER.length] ?? "⠋";
  const lines: string[] = [
    truncate(
      theme.fg(headingColor, headingIcon) +
        " " +
        theme.fg(headingColor, "Agents"),
    ),
  ];

  const finishedLines = finishedTasks.map((task) =>
    truncate(theme.fg("dim", "├─") + ` ${renderFinishedLine(task, theme)}`),
  );
  const runningLines = activeTasks.map((task) => {
    const stats: string[] = [];
    stats.push(formatTurns(task.turnCount));
    if (task.toolUses > 0)
      stats.push(`${task.toolUses} tool use${task.toolUses === 1 ? "" : "s"}`);
    if (task.tokenCount > 0) stats.push(formatTokens(task.tokenCount));
    if (task.startedAt) stats.push(formatDuration(task.startedAt));

    return [
      truncate(
        theme.fg("dim", "├─") +
          ` ${theme.fg("accent", spinner)} ${theme.bold("Explore")}  ${theme.fg("muted", taskLabel(task))} ${theme.fg("dim", "·")} ${theme.fg("dim", stats.join(" · "))}`,
      ),
      truncate(
        theme.fg("dim", "│  ") +
          theme.fg("dim", `  ⎿  ${describeActivity(task)}`),
      ),
    ];
  });

  const queuedLine =
    pendingTasks.length > 0
      ? truncate(
          theme.fg("dim", "├─") +
            ` ${theme.fg("muted", "◦")} ${theme.fg("dim", `${pendingTasks.length} queued`)}`,
        )
      : undefined;

  const maxBody = MAX_WIDGET_LINES - 1;
  const totalBody =
    finishedLines.length + runningLines.length * 2 + (queuedLine ? 1 : 0);

  if (totalBody <= maxBody) {
    lines.push(...finishedLines);
    for (const pair of runningLines) lines.push(...pair);
    if (queuedLine) lines.push(queuedLine);

    if (lines.length > 1) {
      const last = lines.length - 1;
      lines[last] = lines[last]!.replace("├─", "└─");
      if (runningLines.length > 0 && !queuedLine) {
        if (last >= 2) {
          lines[last - 1] = lines[last - 1]!.replace("├─", "└─");
          lines[last] = lines[last]!.replace("│  ", "   ");
        }
      }
    }

    return lines;
  }

  let budget = maxBody - 1;
  let hiddenRunning = 0;
  let hiddenFinished = 0;

  for (const pair of runningLines) {
    if (budget >= 2) {
      lines.push(...pair);
      budget -= 2;
    } else {
      hiddenRunning++;
    }
  }

  if (queuedLine && budget >= 1) {
    lines.push(queuedLine);
    budget--;
  }

  for (const line of finishedLines) {
    if (budget >= 1) {
      lines.push(line);
      budget--;
    } else {
      hiddenFinished++;
    }
  }

  const overflowParts: string[] = [];
  if (hiddenRunning > 0) overflowParts.push(`${hiddenRunning} running`);
  if (hiddenFinished > 0) overflowParts.push(`${hiddenFinished} finished`);
  lines.push(
    truncate(
      theme.fg("dim", "└─") +
        ` ${theme.fg("dim", `+${hiddenRunning + hiddenFinished} more (${overflowParts.join(", ")})`)}`,
    ),
  );
  return lines;
}

export class ExploreWidget {
  private uiCtx: UICtx | undefined;
  private widgetFrame = 0;
  private widgetInterval: ReturnType<typeof setInterval> | undefined;
  private widgetRegistered = false;
  private tui: any | undefined;
  private lastStatusText: string | undefined;

  constructor(private getRuns: () => ExploreRunState[]) {}

  setUICtx(ctx: UICtx | undefined) {
    if (!ctx) return;
    if (ctx !== this.uiCtx) {
      this.uiCtx = ctx;
      this.widgetRegistered = false;
      this.tui = undefined;
      this.lastStatusText = undefined;
    }
  }

  private ensureTimer() {
    if (!this.widgetInterval) {
      this.widgetInterval = setInterval(() => this.update(), 80);
    }
  }

  update() {
    if (!this.uiCtx) return;
    const runs = this.getRuns();
    const activeTasks = runs.flatMap((run) =>
      run.tasks.filter((task) => task.state === "running"),
    );
    const pendingTasks = runs.flatMap((run) =>
      run.tasks.filter((task) => task.state === "pending"),
    );
    const finishedTasks = runs.flatMap((run) =>
      run.tasks.filter(shouldShowFinishedTask),
    );
    const hasAnything =
      activeTasks.length > 0 ||
      pendingTasks.length > 0 ||
      finishedTasks.length > 0;

    if (!hasAnything) {
      if (this.widgetRegistered) {
        this.uiCtx.setWidget("explore-subagent", undefined);
        this.widgetRegistered = false;
        this.tui = undefined;
      }
      if (this.lastStatusText !== undefined) {
        this.uiCtx.setStatus("explore-subagent", undefined);
        this.lastStatusText = undefined;
      }
      if (this.widgetInterval) {
        clearInterval(this.widgetInterval);
        this.widgetInterval = undefined;
      }
      return;
    }

    this.ensureTimer();
    this.widgetFrame++;

    let newStatusText: string | undefined;
    if (activeTasks.length > 0 || pendingTasks.length > 0) {
      const statusParts: string[] = [];
      if (activeTasks.length > 0)
        statusParts.push(`${activeTasks.length} running`);
      if (pendingTasks.length > 0)
        statusParts.push(`${pendingTasks.length} queued`);
      const total = activeTasks.length + pendingTasks.length;
      newStatusText = `${statusParts.join(", ")} agent${total === 1 ? "" : "s"}`;
    }

    if (newStatusText !== this.lastStatusText) {
      this.uiCtx.setStatus("explore-subagent", newStatusText);
      this.lastStatusText = newStatusText;
    }

    if (!this.widgetRegistered) {
      this.uiCtx.setWidget(
        "explore-subagent",
        (tui, theme) => {
          this.tui = tui;
          return {
            render: () =>
              buildWidgetLines(
                this.getRuns(),
                this.widgetFrame,
                theme,
                tui.terminal.columns,
              ),
            invalidate: () => {
              this.widgetRegistered = false;
              this.tui = undefined;
            },
          };
        },
        { placement: "aboveEditor" },
      );
      this.widgetRegistered = true;
    } else {
      this.tui?.requestRender();
    }
  }

  dispose() {
    if (this.widgetInterval) {
      clearInterval(this.widgetInterval);
      this.widgetInterval = undefined;
    }
    if (this.uiCtx) {
      this.uiCtx.setWidget("explore-subagent", undefined);
      this.uiCtx.setStatus("explore-subagent", undefined);
    }
    this.widgetRegistered = false;
    this.tui = undefined;
    this.lastStatusText = undefined;
  }
}

function summarizeTaskResult(result: ExploreTaskResult): string {
  if (result.summary?.trim()) return truncateLine(result.summary, 90);
  if (result.error?.trim()) return truncateLine(result.error, 90);
  return "No summary returned.";
}

function renderFinalTaskBlock(
  result: ExploreTaskResult,
  taskState: ExploreTaskState | undefined,
  expanded: boolean,
  theme: Theme,
): string {
  const isError = result.status === "error" || result.status === "aborted";
  const icon = isError ? theme.fg("error", "✗") : theme.fg("success", "✓");
  const statusText = isError
    ? theme.fg(
        result.status === "aborted" ? "warning" : "error",
        result.status === "aborted" ? "aborted" : "error",
      )
    : theme.fg("dim", "completed");

  const stats: string[] = [];
  if (taskState?.turnCount) stats.push(formatTurns(taskState.turnCount));
  if (taskState?.toolUses)
    stats.push(
      `${taskState.toolUses} tool use${taskState.toolUses === 1 ? "" : "s"}`,
    );
  if (taskState?.tokenCount) stats.push(formatTokens(taskState.tokenCount));
  if (taskState?.startedAt)
    stats.push(formatDuration(taskState.startedAt, taskState.endedAt));

  let block = `${icon} ${theme.bold(taskLabel(result))} ${theme.fg("dim", statusText)}`;
  if (stats.length > 0) {
    block += `\n  ${stats.map((part) => theme.fg("dim", part)).join(` ${theme.fg("dim", "·")} `)}`;
  }

  if (expanded) {
    const sections: string[] = [];
    if (result.summary) sections.push(result.summary.trim());
    if (result.sources?.length)
      sections.push(
        `Sources:\n${result.sources.map((item) => `- ${item}`).join("\n")}`,
      );
    if (result.keyFindings?.length)
      sections.push(
        `Key Findings:\n${result.keyFindings.map((item) => `- ${item}`).join("\n")}`,
      );
    if (result.suggestedNextSteps?.length)
      sections.push(
        `Next Steps:\n${result.suggestedNextSteps.map((item) => `- ${item}`).join("\n")}`,
      );
    if (result.error) sections.push(`Error: ${result.error}`);
    for (const line of sections.join("\n\n").split("\n").slice(0, 40)) {
      block += `\n${theme.fg("dim", `  ${line}`)}`;
    }
  } else {
    block += `\n  ${theme.fg("dim", `⎿  ${summarizeTaskResult(result)}`)}`;
  }

  return block;
}

export function renderExploreToolCall(
  args: { task?: string; tasks?: Array<{ task: string }> },
  theme: Theme,
) {
  const count = Array.isArray(args.tasks) ? args.tasks.length : 1;
  const firstTask = Array.isArray(args.tasks) ? args.tasks[0]?.task : args.task;
  let text = `${theme.fg("toolTitle", theme.bold("Explore"))} `;
  text += theme.fg(
    "accent",
    count > 1
      ? `${count} tasks`
      : taskLabel({
          task: firstTask ?? "Explore task",
          status: "success",
          summary: "",
        } as ExploreTaskResult),
  );
  return new Text(text, 0, 0);
}

export function renderExploreTaskMessage(
  details: {
    taskId: string;
    task: string;
  },
  expanded: boolean,
  theme: Theme,
) {
  const title = `${theme.bold("Explore")}  ${theme.fg("muted", taskLabel({ task: details.task, status: "success", summary: "" } as ExploreTaskResult))}`;
  const status = theme.fg("dim", `  Running (ID: ${details.taskId})`);
  if (!expanded) {
    return new Text(`${title}\n${status}`, 0, 0);
  }
  return new Text(`${title}\n${status}\n${theme.fg("dim", `  Task: ${details.task}`)}`, 0, 0);
}

export function renderExploreToolResult(
  result: { details?: any; content: Array<{ type: string; text?: string }> },
  options: { expanded: boolean; isPartial: boolean },
  theme: Theme,
) {
  const details = result.details ?? {};
  const run = details.run ?? details;
  if (!run || !Array.isArray(run.tasks)) {
    const text =
      result.content[0]?.type === "text" ? (result.content[0].text ?? "") : "";
    return new Text(
      text || (options.isPartial ? "Exploring..." : "No details"),
      0,
      0,
    );
  }

  if (options.isPartial) {
    const count = Array.isArray(run.tasks) ? run.tasks.length : 0;
    const label = count <= 1 ? "Launching exploration subagent…" : `Launching ${count} exploration subagents…`;
    return new Text(theme.fg("dim", label), 0, 0);
  }

  const results = Array.isArray(details.results)
    ? (details.results as ExploreTaskResult[])
    : [];
  const blocks = results.map((taskResult, index) =>
    renderFinalTaskBlock(taskResult, run.tasks[index], options.expanded, theme),
  );
  return new Text(blocks.join("\n\n"), 0, 0);
}
