import fs from "node:fs";
import path from "node:path";
import { Text } from "@mariozechner/pi-tui";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { parseBullets, splitMarkdownSections, shortenPath, shortTaskId } from "./formatting.js";
import { DEFAULT_REVIEWERS } from "./review-config.js";
import type { ParsedSubagentOutput, SubagentTaskInput, SubagentTaskResult } from "./types.js";
import type { Theme } from "./ui.js";

const MAX_DIFF_CHARS = 60_000;
const MAX_UNTRACKED_PREVIEW_BYTES = 16_000;
const MAX_UNTRACKED_PREVIEW_LINES = 160;
const EMPTY_TREE_HASH = "4b825dc642cb6eb9a060e54bf8d69288fbee4904";

type ReviewParams = {
  prompt?: string;
  cwd?: string;
  target?: "working-tree" | "staged";
  baseRef?: string;
  files?: string[];
};

type ReviewContext = {
  repoRoot: string;
  target: "working-tree" | "staged";
  baseRef: string;
  statusShort: string;
  diffStat: string;
  changedFiles: string[];
  diffPreview: string;
  diffWasTruncated: boolean;
};

type GitCommandResult = {
  stdout: string;
  stderr: string;
  code: number;
};

type ResolvedBaseRef = {
  displayBaseRef: string;
  diffBaseRef: string;
};

async function runGit(
  pi: ExtensionAPI,
  cwd: string,
  args: string[],
  signal?: AbortSignal,
): Promise<GitCommandResult> {
  const result = await pi.exec("git", args, { cwd, signal } as any);
  return {
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
    code: result.code ?? 1,
  };
}

function normalizeList(list: string[] | undefined): string[] {
  return (list ?? []).map((item) => item.trim()).filter(Boolean);
}

function uniqueStrings(items: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const item of items) {
    if (seen.has(item)) continue;
    seen.add(item);
    result.push(item);
  }
  return result;
}

async function resolveBaseRef(
  pi: ExtensionAPI,
  repoRoot: string,
  baseRef: string,
  signal?: AbortSignal,
): Promise<ResolvedBaseRef> {
  const result = await runGit(pi, repoRoot, ["rev-parse", "--verify", "--quiet", `${baseRef}^{commit}`], signal);
  if (result.code === 0) {
    return {
      diffBaseRef: baseRef,
      displayBaseRef: baseRef,
    };
  }

  if (baseRef === "HEAD") {
    return {
      diffBaseRef: EMPTY_TREE_HASH,
      displayBaseRef: "HEAD (unborn; empty tree)",
    };
  }

  throw new Error(`Invalid or unknown baseRef: ${baseRef}`);
}

function formatUntrackedDiffStat(untrackedFiles: string[]): string | undefined {
  if (untrackedFiles.length === 0) return undefined;
  return [
    "Untracked files:",
    ...untrackedFiles.map((file) => `- ${file} (untracked)`),
  ].join("\n");
}

function readUntrackedPreview(absolutePath: string): { sample: Buffer; truncated: boolean } {
  const fd = fs.openSync(absolutePath, "r");
  try {
    const sample = Buffer.alloc(MAX_UNTRACKED_PREVIEW_BYTES + 1);
    const bytesRead = fs.readSync(fd, sample, 0, sample.length, 0);
    return {
      sample: sample.subarray(0, bytesRead),
      truncated: bytesRead > MAX_UNTRACKED_PREVIEW_BYTES,
    };
  } finally {
    fs.closeSync(fd);
  }
}

function buildUntrackedFilePreview(repoRoot: string, file: string): string {
  const absolutePath = path.join(repoRoot, file);

  try {
    const { sample, truncated: truncatedByBytes } = readUntrackedPreview(absolutePath);
    const previewSample = sample.subarray(0, MAX_UNTRACKED_PREVIEW_BYTES);
    if (previewSample.includes(0)) {
      return [
        `diff --git a/${file} b/${file}`,
        "new file mode 100644",
        "--- /dev/null",
        `+++ b/${file}`,
        "Binary file preview omitted for untracked file.",
      ].join("\n");
    }

    const previewText = previewSample.toString("utf8").replace(/\r\n/g, "\n");
    const allPreviewLines = previewText.split("\n");
    const previewLines = allPreviewLines.slice(0, MAX_UNTRACKED_PREVIEW_LINES);
    const truncated = truncatedByBytes || allPreviewLines.length > MAX_UNTRACKED_PREVIEW_LINES;

    const bodyLines = previewLines.map((line) => `+${line}`);
    if (truncated) bodyLines.push("+[... truncated]");

    return [
      `diff --git a/${file} b/${file}`,
      "new file mode 100644",
      "--- /dev/null",
      `+++ b/${file}`,
      `@@ -0,0 +1,${Math.max(previewLines.length, 1)} @@`,
      ...bodyLines,
    ].join("\n");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return [
      `diff --git a/${file} b/${file}`,
      "new file mode 100644",
      "--- /dev/null",
      `+++ b/${file}`,
      `Unable to read untracked file preview: ${message}`,
    ].join("\n");
  }
}

function buildUntrackedDiffPreview(repoRoot: string, untrackedFiles: string[]): string | undefined {
  if (untrackedFiles.length === 0) return undefined;
  return untrackedFiles.map((file) => buildUntrackedFilePreview(repoRoot, file)).join("\n\n");
}

function buildCombinedDiffPreview(repoRoot: string, diffText: string, untrackedFiles: string[]): string {
  const sections = [diffText.trim(), buildUntrackedDiffPreview(repoRoot, untrackedFiles)]
    .map((section) => section?.trim())
    .filter(Boolean);
  return sections.join("\n\n");
}

async function collectReviewContext(
  pi: ExtensionAPI,
  cwd: string,
  params: ReviewParams,
  signal?: AbortSignal,
): Promise<ReviewContext> {
  const repoResult = await runGit(pi, cwd, ["rev-parse", "--show-toplevel"], signal);
  if (repoResult.code !== 0) {
    throw new Error(`Not inside a git repository: ${repoResult.stderr.trim() || repoResult.stdout.trim() || cwd}`);
  }

  const repoRoot = repoResult.stdout.trim();
  const target = params.target ?? "working-tree";
  const requestedBaseRef = params.baseRef?.trim() || "HEAD";
  const files = normalizeList(params.files);
  const diffBaseArgs = ["diff", ...(target === "staged" ? ["--cached"] : [])];
  const diffTail = files.length > 0 ? ["--", ...files] : [];
  const { diffBaseRef, displayBaseRef } = await resolveBaseRef(pi, repoRoot, requestedBaseRef, signal);

  const statusArgs = ["status", "--short", "--untracked-files=all", ...(files.length > 0 ? ["--", ...files] : [])];
  const untrackedPromise = target === "working-tree"
    ? runGit(pi, repoRoot, ["ls-files", "--others", "--exclude-standard", ...diffTail], signal)
    : Promise.resolve({ stdout: "", stderr: "", code: 0 });

  const [statusResult, statResult, filesResult, diffResult, untrackedResult] = await Promise.all([
    runGit(pi, repoRoot, statusArgs, signal),
    runGit(pi, repoRoot, [...diffBaseArgs, "--stat", diffBaseRef, ...diffTail], signal),
    runGit(pi, repoRoot, [...diffBaseArgs, "--name-only", diffBaseRef, ...diffTail], signal),
    runGit(pi, repoRoot, [...diffBaseArgs, "--unified=3", diffBaseRef, ...diffTail], signal),
    untrackedPromise,
  ]);

  if (statResult.code !== 0 || filesResult.code !== 0 || diffResult.code !== 0 || untrackedResult.code !== 0) {
    const errorText = [statResult.stderr, filesResult.stderr, diffResult.stderr, untrackedResult.stderr]
      .map((part) => part.trim())
      .filter(Boolean)
      .join("\n");
    throw new Error(errorText || "Failed to collect git diff for review.");
  }

  const diffFiles = filesResult.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  const untrackedFiles = untrackedResult.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  const changedFiles = uniqueStrings([...diffFiles, ...untrackedFiles]);

  if (changedFiles.length === 0) {
    throw new Error("No matching changes to review.");
  }

  const diffStat = [statResult.stdout.trim(), formatUntrackedDiffStat(untrackedFiles)]
    .filter(Boolean)
    .join("\n\n");
  const fullDiff = buildCombinedDiffPreview(repoRoot, diffResult.stdout.trim(), untrackedFiles);
  const diffWasTruncated = fullDiff.length > MAX_DIFF_CHARS;
  const diffPreview = diffWasTruncated ? `${fullDiff.slice(0, MAX_DIFF_CHARS)}\n\n[diff truncated]` : fullDiff;

  return {
    repoRoot,
    target,
    baseRef: displayBaseRef,
    statusShort: statusResult.stdout.trim(),
    diffStat,
    changedFiles,
    diffPreview,
    diffWasTruncated,
  };
}

function buildReviewTask(
  context: ReviewContext,
  reviewer: { label?: string; model: string; focus?: string },
  extraPrompt?: string,
): string {
  const changedFilesText = context.changedFiles.map((file) => `- ${file}`).join("\n");
  const focus = reviewer.focus?.trim() || "general code review";
  const lines: string[] = [
    `Working directory: ${context.repoRoot}`,
    `Repository root for local inspection: ${context.repoRoot}`,
    `For repository-local investigation, only inspect paths under ${context.repoRoot}.`,
    `Review focus: ${focus}`,
    "Review only the code changes described below.",
    "Use the diff as the primary review target, and inspect changed files directly when you need surrounding context.",
    "The changed files list may include untracked working-tree files, which are also included in the review context below.",
    "Only report actionable issues that are reasonably likely to be real.",
    "Do not report style-only nits unless the prompt explicitly asks for them.",
    "If you think there are no actionable issues, say so clearly.",
    "Emit one short [[progress]] block early in the review, then update it only if your plan materially changes.",
  ];

  if (extraPrompt?.trim()) {
    lines.push(`Additional instructions: ${extraPrompt.trim()}`);
  }

  lines.push(
    "",
    "Return markdown with exactly these sections:",
    "## Summary",
    "A short paragraph describing the overall review conclusion.",
    "",
    "## Findings",
    "- One bullet per actionable finding.",
    "- Format each bullet as: `[severity: high|medium|low][confidence: high|medium|low][path: <file or file:line>] issue | evidence | recommendation`",
    "- If there are no actionable findings, write `- None`.",
    "",
    "## Next Steps",
    "- Optional follow-up suggestions. Use bullets. If there are none, write `- None`.",
    "",
    "Review context:",
    `- Target: ${context.target}`,
    `- Base ref: ${context.baseRef}`,
    `- Repo root: ${context.repoRoot}`,
    `- Diff truncated: ${context.diffWasTruncated ? "yes" : "no"}`,
    "",
    "Changed files:",
    changedFilesText,
    "",
    "Git status (--short):",
    context.statusShort || "(clean status output)",
    "",
    "Diff stat:",
    context.diffStat || "(no diff stat)",
    "",
    "Diff preview:",
    context.diffPreview || "(no diff)",
  );

  return lines.join("\n");
}

export async function createReviewTasks(
  pi: ExtensionAPI,
  params: ReviewParams,
  defaultCwd: string,
  signal?: AbortSignal,
): Promise<{ tasks: SubagentTaskInput[]; context: ReviewContext }> {
  const cwd = params.cwd?.trim() || defaultCwd;
  const context = await collectReviewContext(pi, cwd, params, signal);
  const reviewers = [...DEFAULT_REVIEWERS];

  return {
    context,
    tasks: reviewers.map((reviewer) => ({
      task: buildReviewTask(context, reviewer, params.prompt),
      label: reviewer.label?.trim() || reviewer.model,
      model: reviewer.model.trim(),
      cwd: context.repoRoot,
      metadata: {
        focus: reviewer.focus?.trim() || undefined,
        reviewerLabel: reviewer.label?.trim() || reviewer.model.trim(),
      },
    })),
  };
}

export function parseReviewOutput(markdown: string): ParsedSubagentOutput {
  const normalized = markdown.trim();
  if (!normalized) return { summary: "" };

  const sections = splitMarkdownSections(normalized);
  const findings = (parseBullets(sections.get("findings")) ?? []).filter((item) => item.toLowerCase() !== "none");
  const suggestedNextSteps = (parseBullets(sections.get("next steps")) ?? []).filter(
    (item) => item.toLowerCase() !== "none",
  );

  return {
    summary: sections.get("summary") ?? normalized,
    data: {
      findings,
      suggestedNextSteps,
    },
  };
}

export function renderFinalReviewResults(
  runId: string,
  mode: "single" | "parallel",
  results: SubagentTaskResult[],
  context?: ReviewContext,
): string {
  const lines: string[] = [];
  lines.push("# Review Results");
  lines.push("");
  lines.push(`- Run ID: ${runId}`);
  lines.push(`- Mode: ${mode}`);
  if (context) {
    lines.push(`- Target: ${context.target}`);
    lines.push(`- Base ref: ${context.baseRef}`);
    lines.push(`- Repo root: ${shortenPath(context.repoRoot)}`);
    lines.push(`- Changed files: ${context.changedFiles.length}`);
  }
  lines.push("");

  for (let i = 0; i < results.length; i++) {
    const result = results[i]!;
    const data = result.data ?? {};
    const findings = Array.isArray(data.findings) ? (data.findings as string[]) : [];
    const suggestedNextSteps = Array.isArray(data.suggestedNextSteps)
      ? (data.suggestedNextSteps as string[])
      : [];
    const focus = typeof result.metadata?.focus === "string" ? result.metadata.focus : undefined;

    lines.push(`## Reviewer ${i + 1}`);
    lines.push(`- Status: ${result.status}`);
    lines.push(`- Task ID: ${result.taskId} (${shortTaskId(result.taskId)})`);
    lines.push(`- Reviewer: ${result.label ?? result.model ?? result.task}`);
    if (result.model) lines.push(`- Model: ${result.model}`);
    if (focus) lines.push(`- Focus: ${focus}`);
    lines.push("");
    lines.push("### Summary");
    lines.push(result.summary || "No summary returned.");
    lines.push("");

    lines.push("### Findings");
    if (findings.length > 0) {
      for (const finding of findings) lines.push(`- ${finding}`);
    } else {
      lines.push("- None");
    }
    lines.push("");

    if (suggestedNextSteps.length > 0) {
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

function summarizeReviewResult(result: SubagentTaskResult): string {
  const findings = Array.isArray(result.data?.findings) ? (result.data?.findings as string[]) : [];
  if (findings.length > 0) return findings[0]!;
  if (result.summary?.trim()) return result.summary.split("\n")[0]!.trim();
  if (result.error?.trim()) return result.error.split("\n")[0]!.trim();
  return "No actionable findings.";
}

function renderFinalTaskBlock(result: SubagentTaskResult, expanded: boolean, theme: Theme): string {
  const isError = result.status === "error" || result.status === "aborted";
  const icon = isError ? theme.fg("error", "✗") : theme.fg("success", "✓");
  const statusText = isError
    ? theme.fg(result.status === "aborted" ? "warning" : "error", result.status === "aborted" ? "aborted" : "error")
    : theme.fg("dim", "completed");
  const focus = typeof result.metadata?.focus === "string" ? result.metadata.focus : undefined;
  const findings = Array.isArray(result.data?.findings) ? (result.data?.findings as string[]) : [];
  const suggestedNextSteps = Array.isArray(result.data?.suggestedNextSteps)
    ? (result.data?.suggestedNextSteps as string[])
    : [];
  const model = result.model?.trim();
  const title = result.label?.trim() || model || result.task;
  const shouldShowModelLine = Boolean(model && result.label?.trim() && result.label.trim() !== model);

  let block = `${icon} ${theme.bold(title)} ${theme.fg("dim", statusText)}`;
  block += `\n  ${theme.fg("dim", `ID: ${shortTaskId(result.taskId)}`)}`;
  if (shouldShowModelLine) block += `\n  ${theme.fg("dim", `Model: ${model}`)}`;
  if (focus) block += `\n  ${theme.fg("dim", `Focus: ${focus}`)}`;

  if (expanded) {
    const sections: string[] = [];
    if (result.summary) sections.push(result.summary.trim());
    sections.push(`Findings:\n${(findings.length > 0 ? findings : ["None"]).map((item) => `- ${item}`).join("\n")}`);
    if (suggestedNextSteps.length > 0) {
      sections.push(`Next Steps:\n${suggestedNextSteps.map((item) => `- ${item}`).join("\n")}`);
    }
    if (result.error) sections.push(`Error: ${result.error}`);
    for (const line of sections.join("\n\n").split("\n").slice(0, 50)) {
      block += `\n${theme.fg("dim", `  ${line}`)}`;
    }
  } else {
    block += `\n  ${theme.fg("dim", `⎿  ${summarizeReviewResult(result)}`)}`;
  }

  return block;
}

export function renderReviewToolCall(
  args: { target?: string },
  theme: Theme,
) {
  const count = DEFAULT_REVIEWERS.length;
  const target = args.target ?? "working-tree";
  let text = `${theme.fg("toolTitle", theme.bold("Review"))} `;
  text += theme.fg("accent", `${count} reviewers`);
  text += theme.fg("muted", ` (${target})`);
  return new Text(text, 0, 0);
}

export function renderReviewToolResult(
  result: { details?: any; content: Array<{ type: string; text?: string }> },
  options: { expanded: boolean; isPartial: boolean },
  theme: Theme,
) {
  const details = result.details ?? {};
  const run = details.run ?? details;
  if (!run || !Array.isArray(run.tasks)) {
    const text = result.content[0]?.type === "text" ? (result.content[0].text ?? "") : "";
    return new Text(text || (options.isPartial ? "Reviewing..." : "No details"), 0, 0);
  }

  if (options.isPartial) {
    const count = Array.isArray(run.tasks) ? run.tasks.length : 0;
    const label = count <= 1 ? "Launching review subagent…" : `Launching ${count} review subagents…`;
    return new Text(theme.fg("dim", label), 0, 0);
  }

  const results = Array.isArray(details.results) ? (details.results as SubagentTaskResult[]) : [];
  const blocks = results.map((taskResult) => renderFinalTaskBlock(taskResult, options.expanded, theme));
  return new Text(blocks.join("\n\n"), 0, 0);
}
