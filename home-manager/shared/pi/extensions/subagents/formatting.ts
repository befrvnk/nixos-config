import * as os from "node:os";
import type { SubagentRunState } from "./types.js";
import { MAX_RECENT_OUTPUT_LINES, MAX_RECENT_TOOLS } from "./types.js";

export function workflowDisplayName(workflow: SubagentRunState["workflow"]): string {
  return workflow === "review" ? "Review" : "Explore";
}

export function shortenPath(filePath: string): string {
  const home = os.homedir();
  return filePath.startsWith(home) ? `~${filePath.slice(home.length)}` : filePath;
}

export function formatDuration(startedAt: number, endedAt?: number): string {
  const elapsed = (endedAt ?? Date.now()) - startedAt;
  if (elapsed < 1000) return `${elapsed}ms`;
  if (elapsed < 60_000) return `${(elapsed / 1000).toFixed(1)}s`;
  const minutes = Math.floor(elapsed / 60_000);
  const seconds = Math.floor((elapsed % 60_000) / 1000);
  return `${minutes}m${seconds}s`;
}

export function parseBullets(sectionBody: string | undefined): string[] | undefined {
  if (!sectionBody) return undefined;
  const items = sectionBody
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("- "))
    .map((line) => line.slice(2).trim())
    .filter(Boolean);
  return items.length > 0 ? items : undefined;
}

export function splitMarkdownSections(markdown: string): Map<string, string> {
  const normalized = markdown.trim();
  const sections = new Map<string, string>();
  if (!normalized) return sections;

  const sectionRegex = /^##\s+(.+)$/gm;
  const matches = [...normalized.matchAll(sectionRegex)];
  for (let i = 0; i < matches.length; i++) {
    const match = matches[i]!;
    const title = match[1]!.trim().toLowerCase();
    const start = match.index! + match[0].length;
    const end = i + 1 < matches.length ? matches[i + 1]!.index! : normalized.length;
    sections.set(title, normalized.slice(start, end).trim());
  }

  if (matches.length === 0) {
    sections.set("summary", normalized);
    return sections;
  }

  const preamble = normalized.slice(0, matches[0]!.index!).trim();
  if (preamble) {
    const existingSummary = sections.get("summary");
    sections.set("summary", existingSummary ? `${preamble}\n\n${existingSummary}` : preamble);
  }

  return sections;
}

export function renderRunMarkdown(run: SubagentRunState): string {
  const lines: string[] = [];
  const workflowName = workflowDisplayName(run.workflow);
  lines.push(`# ${workflowName} ${run.runId}`);
  lines.push("");
  lines.push(`- Workflow: ${run.workflow}`);
  lines.push(`- Mode: ${run.mode}`);
  lines.push(`- State: ${run.state}`);
  lines.push(`- Started: ${new Date(run.startedAt).toLocaleTimeString()}`);
  lines.push(`- Elapsed: ${formatDuration(run.startedAt, run.endedAt)}`);
  lines.push("");

  for (const task of run.tasks) {
    lines.push(`## Task ${task.index + 1} — ${task.state}`);
    lines.push(`- Label: ${task.label}`);
    lines.push(`- Task: ${task.task}`);
    if (task.model) lines.push(`- Model: ${task.model}`);
    if (task.cwd) lines.push(`- CWD: ${shortenPath(task.cwd)}`);
    if (task.currentTool) lines.push(`- Current tool: ${task.currentTool}`);
    if (task.turnCount > 0) lines.push(`- Turns: ${task.turnCount}`);
    if (task.toolUses > 0) lines.push(`- Tool uses: ${task.toolUses}`);
    if (task.tokenCount > 0) lines.push(`- Tokens: ${task.tokenCount}`);
    if (task.progressItems && task.progressItems.length > 0) {
      lines.push("- Progress:");
      for (const item of task.progressItems.slice(0, 6)) {
        lines.push(`  - [${item.done ? "x" : " "}] ${item.text}`);
      }
    }
    if (task.recentTools.length > 0) {
      lines.push("- Recent tools:");
      for (const tool of task.recentTools.slice(-MAX_RECENT_TOOLS)) lines.push(`  - ${tool}`);
    }
    if (task.recentOutputLines.length > 0) {
      lines.push("- Recent output:");
      for (const line of task.recentOutputLines.slice(-MAX_RECENT_OUTPUT_LINES)) lines.push(`  - ${line}`);
    }
    if (task.summary) lines.push(`- Summary: ${task.summary}`);
    if (task.error) lines.push(`- Error: ${task.error}`);
    lines.push("");
  }

  return lines.join("\n").trim();
}

export function serializeRun(run: SubagentRunState) {
  return {
    workflow: run.workflow,
    runId: run.runId,
    mode: run.mode,
    state: run.state,
    startedAt: run.startedAt,
    endedAt: run.endedAt,
    tasks: run.tasks.map((task) => ({
      workflow: task.workflow,
      index: task.index,
      taskId: task.taskId,
      task: task.task,
      label: task.label,
      model: task.model,
      cwd: task.cwd,
      metadata: task.metadata,
      state: task.state,
      currentTool: task.currentTool,
      toolUses: task.toolUses,
      turnCount: task.turnCount,
      tokenCount: task.tokenCount,
      responseText: task.responseText,
      progressItems: task.progressItems ? [...task.progressItems] : undefined,
      recentTools: [...task.recentTools],
      recentOutputLines: [...task.recentOutputLines],
      summary: task.summary,
      data: task.data,
      error: task.error,
      startedAt: task.startedAt,
      endedAt: task.endedAt,
    })),
  };
}
