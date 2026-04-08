import { Text } from "@mariozechner/pi-tui";
import {
  parseBullets,
  splitMarkdownSections,
  shortenPath,
} from "./formatting.js";
import type { ParsedSubagentOutput, SubagentTaskResult } from "./types.js";
import type { Theme } from "./ui.js";

export function parseExploreOutput(markdown: string): ParsedSubagentOutput {
  const normalized = markdown.trim();
  if (!normalized) return { summary: "" };

  const sections = splitMarkdownSections(normalized);
  return {
    summary: sections.get("summary") ?? normalized,
    data: {
      sources: parseBullets(sections.get("sources")),
      keyFindings: parseBullets(sections.get("key findings")),
      suggestedNextSteps: parseBullets(sections.get("next steps")),
    },
  };
}

export function renderFinalExploreResults(
  runId: string,
  mode: "single" | "parallel",
  results: SubagentTaskResult[],
): string {
  const lines: string[] = [];
  lines.push("# Exploration Results");
  lines.push("");
  lines.push(`- Run ID: ${runId}`);
  lines.push(`- Mode: ${mode}`);
  lines.push("");

  for (let i = 0; i < results.length; i++) {
    const result = results[i]!;
    const data = result.data ?? {};
    const sources = Array.isArray(data.sources) ? (data.sources as string[]) : undefined;
    const keyFindings = Array.isArray(data.keyFindings) ? (data.keyFindings as string[]) : undefined;
    const suggestedNextSteps = Array.isArray(data.suggestedNextSteps)
      ? (data.suggestedNextSteps as string[])
      : undefined;

    lines.push(`## Task ${i + 1}`);
    lines.push(`- Status: ${result.status}`);
    lines.push(`- Label: ${result.label ?? result.task}`);
    lines.push(`- Task: ${result.task}`);
    if (result.model) lines.push(`- Model: ${result.model}`);
    if (result.cwd) lines.push(`- CWD: ${shortenPath(result.cwd)}`);
    lines.push("");
    lines.push("### Summary");
    lines.push(result.summary || "No summary returned.");
    lines.push("");

    if (sources && sources.length > 0) {
      lines.push("### Sources");
      for (const source of sources) lines.push(`- ${source}`);
      lines.push("");
    }

    if (keyFindings && keyFindings.length > 0) {
      lines.push("### Key Findings");
      for (const finding of keyFindings) lines.push(`- ${finding}`);
      lines.push("");
    }

    if (suggestedNextSteps && suggestedNextSteps.length > 0) {
      lines.push("### Next Steps");
      for (const step of suggestedNextSteps) lines.push(`- ${step}`);
      lines.push("");
    }

    if (result.error) {
      lines.push("### Error");
      lines.push(result.error);
      lines.push("");
    }
  }

  return lines.join("\n").trim();
}

function summarizeTaskResult(result: SubagentTaskResult): string {
  if (result.summary?.trim()) return result.summary.split("\n")[0]!.trim();
  if (result.error?.trim()) return result.error.split("\n")[0]!.trim();
  return "No summary returned.";
}

function renderFinalTaskBlock(result: SubagentTaskResult, expanded: boolean, theme: Theme): string {
  const isError = result.status === "error" || result.status === "aborted";
  const icon = isError ? theme.fg("error", "✗") : theme.fg("success", "✓");
  const statusText = isError
    ? theme.fg(result.status === "aborted" ? "warning" : "error", result.status === "aborted" ? "aborted" : "error")
    : theme.fg("dim", "completed");
  const data = result.data ?? {};
  const sources = Array.isArray(data.sources) ? (data.sources as string[]) : undefined;
  const keyFindings = Array.isArray(data.keyFindings) ? (data.keyFindings as string[]) : undefined;
  const suggestedNextSteps = Array.isArray(data.suggestedNextSteps)
    ? (data.suggestedNextSteps as string[])
    : undefined;

  let block = `${icon} ${theme.bold(result.label ?? result.task)} ${theme.fg("dim", statusText)}`;

  if (expanded) {
    const sections: string[] = [];
    if (result.summary) sections.push(result.summary.trim());
    if (sources?.length) sections.push(`Sources:\n${sources.map((item) => `- ${item}`).join("\n")}`);
    if (keyFindings?.length) sections.push(`Key Findings:\n${keyFindings.map((item) => `- ${item}`).join("\n")}`);
    if (suggestedNextSteps?.length) {
      sections.push(`Next Steps:\n${suggestedNextSteps.map((item) => `- ${item}`).join("\n")}`);
    }
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
  text += theme.fg("accent", count > 1 ? `${count} tasks` : firstTask?.split("\n")[0]?.trim() || "task");
  return new Text(text, 0, 0);
}

export function renderExploreToolResult(
  result: { details?: any; content: Array<{ type: string; text?: string }> },
  options: { expanded: boolean; isPartial: boolean },
  theme: Theme,
) {
  const details = result.details ?? {};
  const run = details.run ?? details;
  if (!run || !Array.isArray(run.tasks)) {
    const text = result.content[0]?.type === "text" ? (result.content[0].text ?? "") : "";
    return new Text(text || (options.isPartial ? "Exploring..." : "No details"), 0, 0);
  }

  if (options.isPartial) {
    const count = Array.isArray(run.tasks) ? run.tasks.length : 0;
    const label = count <= 1 ? "Launching exploration subagent…" : `Launching ${count} exploration subagents…`;
    return new Text(theme.fg("dim", label), 0, 0);
  }

  const results = Array.isArray(details.results) ? (details.results as SubagentTaskResult[]) : [];
  const blocks = results.map((taskResult) => renderFinalTaskBlock(taskResult, options.expanded, theme));
  return new Text(blocks.join("\n\n"), 0, 0);
}
