import * as os from "node:os";
import type { ExploreRunState, ExploreTaskResult } from "./types.js";
import { MAX_RECENT_OUTPUT_LINES, MAX_RECENT_TOOLS } from "./types.js";

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

export function renderRunMarkdown(run: ExploreRunState): string {
  const lines: string[] = [];
  lines.push(`# Explore ${run.runId}`);
  lines.push("");
  lines.push(`- Mode: ${run.mode}`);
  lines.push(`- State: ${run.state}`);
  lines.push(`- Started: ${new Date(run.startedAt).toLocaleTimeString()}`);
  lines.push(`- Elapsed: ${formatDuration(run.startedAt, run.endedAt)}`);
  lines.push("");

  for (const task of run.tasks) {
    lines.push(`## Task ${task.index + 1} — ${task.state}`);
    lines.push(`- Task: ${task.task}`);
    if (task.model) lines.push(`- Model: ${task.model}`);
    if (task.cwd) lines.push(`- CWD: ${shortenPath(task.cwd)}`);
    if (task.currentTool) lines.push(`- Current tool: ${task.currentTool}`);
    if (task.turnCount > 0) lines.push(`- Turns: ${task.turnCount}`);
    if (task.toolUses > 0) lines.push(`- Tool uses: ${task.toolUses}`);
    if (task.tokenCount > 0) lines.push(`- Tokens: ${task.tokenCount}`);
    if (task.recentTools.length > 0) {
      lines.push(`- Recent tools:`);
      for (const tool of task.recentTools.slice(-MAX_RECENT_TOOLS)) lines.push(`  - ${tool}`);
    }
    if (task.recentOutputLines.length > 0) {
      lines.push(`- Recent output:`);
      for (const line of task.recentOutputLines.slice(-MAX_RECENT_OUTPUT_LINES)) lines.push(`  - ${line}`);
    }
    if (task.summary) lines.push(`- Summary: ${task.summary}`);
    if (task.error) lines.push(`- Error: ${task.error}`);
    lines.push("");
  }

  return lines.join("\n").trim();
}

export function renderFinalExploreResults(runId: string, mode: "single" | "parallel", results: ExploreTaskResult[]): string {
  const lines: string[] = [];
  lines.push(`# Exploration Results`);
  lines.push("");
  lines.push(`- Run ID: ${runId}`);
  lines.push(`- Mode: ${mode}`);
  lines.push("");

  for (let i = 0; i < results.length; i++) {
    const result = results[i]!;
    lines.push(`## Task ${i + 1}`);
    lines.push(`- Status: ${result.status}`);
    lines.push(`- Task: ${result.task}`);
    if (result.model) lines.push(`- Model: ${result.model}`);
    if (result.cwd) lines.push(`- CWD: ${shortenPath(result.cwd)}`);
    lines.push("");
    lines.push(`### Summary`);
    lines.push(result.summary || "No summary returned.");
    lines.push("");

    if (result.sources && result.sources.length > 0) {
      lines.push(`### Sources`);
      for (const source of result.sources) lines.push(`- ${source}`);
      lines.push("");
    }

    if (result.keyFindings && result.keyFindings.length > 0) {
      lines.push(`### Key Findings`);
      for (const finding of result.keyFindings) lines.push(`- ${finding}`);
      lines.push("");
    }

    if (result.suggestedNextSteps && result.suggestedNextSteps.length > 0) {
      lines.push(`### Next Steps`);
      for (const step of result.suggestedNextSteps) lines.push(`- ${step}`);
      lines.push("");
    }

    if (result.error) {
      lines.push(`### Error`);
      lines.push(result.error);
      lines.push("");
    }
  }

  return lines.join("\n").trim();
}

function parseBullets(sectionBody: string | undefined): string[] | undefined {
  if (!sectionBody) return undefined;
  const items = sectionBody
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("- "))
    .map((line) => line.slice(2).trim())
    .filter(Boolean);
  return items.length > 0 ? items : undefined;
}

export function parseStructuredOutput(markdown: string): Omit<ExploreTaskResult, "task" | "model" | "cwd" | "status"> {
  const normalized = markdown.trim();
  if (!normalized) return { summary: "" };

  const sectionRegex = /^##\s+(.+)$/gm;
  const sections = new Map<string, string>();
  const matches = [...normalized.matchAll(sectionRegex)];
  for (let i = 0; i < matches.length; i++) {
    const match = matches[i]!;
    const title = match[1]!.trim().toLowerCase();
    const start = match.index! + match[0].length;
    const end = i + 1 < matches.length ? matches[i + 1]!.index! : normalized.length;
    sections.set(title, normalized.slice(start, end).trim());
  }

  const summary = sections.get("summary") ?? normalized;
  return {
    summary,
    sources: parseBullets(sections.get("sources")),
    keyFindings: parseBullets(sections.get("key findings")),
    suggestedNextSteps: parseBullets(sections.get("next steps")),
  };
}

export function serializeRun(run: ExploreRunState) {
  return {
    runId: run.runId,
    mode: run.mode,
    state: run.state,
    startedAt: run.startedAt,
    endedAt: run.endedAt,
    tasks: run.tasks.map((task) => ({
      index: task.index,
      taskId: task.taskId,
      task: task.task,
      model: task.model,
      cwd: task.cwd,
      state: task.state,
      currentTool: task.currentTool,
      toolUses: task.toolUses,
      turnCount: task.turnCount,
      tokenCount: task.tokenCount,
      responseText: task.responseText,
      recentTools: [...task.recentTools],
      recentOutputLines: [...task.recentOutputLines],
      summary: task.summary,
      sources: task.sources,
      keyFindings: task.keyFindings,
      suggestedNextSteps: task.suggestedNextSteps,
      error: task.error,
      startedAt: task.startedAt,
      endedAt: task.endedAt,
    })),
  };
}
