import type { QueryAction, ServerStatus } from "./types.js";

export type WarmupSummary = {
  language: ServerStatus["language"];
  root: string;
  state: ServerStatus["state"];
  elapsedMs: number;
  lastFailure?: ServerStatus["lastFailure"];
};

function formatElapsed(elapsedMs: number): string {
  if (elapsedMs < 1000) return `${elapsedMs}ms`;
  return `${(elapsedMs / 1000).toFixed(elapsedMs >= 10_000 ? 0 : 1)}s`;
}

export function summarizeWarmupStatus(status: ServerStatus): WarmupSummary {
  const startedAt = status.startedAt ?? Date.now();
  return {
    language: status.language,
    root: status.root,
    state: status.state,
    elapsedMs: Math.max(0, Date.now() - startedAt),
    lastFailure: status.lastFailure,
  };
}

export function formatWarmupMessage(action: QueryAction, summary: WarmupSummary): string {
  const lines = [
    `${summary.language} LSP is still warming up.`,
    `Action: ${action}`,
    `Root: ${summary.root}`,
    `State: ${summary.state}`,
    `Elapsed: ${formatElapsed(summary.elapsedMs)}`,
  ];

  if (summary.lastFailure) {
    lines.push(`Last failure: ${summary.lastFailure.category}: ${summary.lastFailure.message}`);
  }

  lines.push("Suggestion: retry shortly or run /lsp-status.");
  return lines.join("\n");
}

export function formatWorkspaceWarmupMessage(action: QueryAction, warmups: WarmupSummary[]): string {
  const uniqueWarmups = warmups.filter(
    (warmup, index) =>
      warmups.findIndex(
        (candidate) => candidate.language === warmup.language && candidate.root === warmup.root,
      ) === index,
  );

  const lines = [`LSP results are still warming up for ${action}:`, ""];
  for (const warmup of uniqueWarmups) {
    lines.push(
      `- ${warmup.language}: ${warmup.state} (${formatElapsed(warmup.elapsedMs)}) — ${warmup.root}`,
    );
  }
  lines.push("", "Suggestion: retry shortly or run /lsp-status.");
  return lines.join("\n");
}
