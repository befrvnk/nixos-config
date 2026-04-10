import {
  parseBullets,
  shortTaskId,
  shortenPath,
  splitMarkdownSections,
} from "../../formatting.js";
import type {
  ParsedSubagentOutput,
  SubagentTaskResult,
} from "../../types.js";

export function asStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter(
        (item): item is string =>
          typeof item === "string" && item.trim().length > 0,
      )
    : [];
}

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
  lines.push(`- Tasks: ${results.length}`);
  lines.push("");

  for (let i = 0; i < results.length; i++) {
    const result = results[i]!;
    const sources = asStringArray(result.data?.sources);
    const keyFindings = asStringArray(result.data?.keyFindings);
    const suggestedNextSteps = asStringArray(result.data?.suggestedNextSteps);

    lines.push(`## Task ${i + 1}`);
    lines.push(`- Status: ${result.status}`);
    lines.push(`- Task ID: ${result.taskId} (${shortTaskId(result.taskId)})`);
    lines.push(`- Label: ${result.label ?? result.task}`);
    if (result.model) lines.push(`- Model: ${result.model}`);
    if (result.cwd) lines.push(`- CWD: ${shortenPath(result.cwd)}`);
    lines.push("");

    lines.push("### Summary");
    lines.push(result.summary || "No summary returned.");
    lines.push("");

    lines.push("### Sources");
    if (sources.length > 0) {
      for (const source of sources) lines.push(`- ${source}`);
    } else {
      lines.push("- None");
    }
    lines.push("");

    lines.push("### Key Findings");
    if (keyFindings.length > 0) {
      for (const finding of keyFindings) lines.push(`- ${finding}`);
    } else {
      lines.push("- None");
    }
    lines.push("");

    lines.push("### Next Steps");
    if (suggestedNextSteps.length > 0) {
      for (const step of suggestedNextSteps) lines.push(`- ${step}`);
    } else {
      lines.push("- None");
    }
    lines.push("");

    if (result.error) {
      lines.push("### Error");
      lines.push(result.error);
      lines.push("");
    }
  }

  return lines.join("\n").trim();
}

export function summarizeExploreResult(result: SubagentTaskResult): string {
  const keyFindings = asStringArray(result.data?.keyFindings);
  if (keyFindings.length > 0) return keyFindings[0]!;
  if (result.summary?.trim()) return result.summary.split("\n")[0]!.trim();
  if (result.error?.trim()) return result.error.split("\n")[0]!.trim();
  return "No summary returned.";
}
