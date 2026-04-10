import { shortTaskId } from "./formatting.js";
import type { SubagentRunState, SubagentWorkflow } from "./types.js";
import type { ReviewCommandRequest } from "./workflows/review/index.js";

export const REVIEW_COMMAND_USAGE = [
  "Usage:",
  "/review",
  "/review uncommitted",
  "/review staged",
  "/review branch <name>",
].join("\n");

export type ReviewSelection = {
  label: string;
  request: ReviewCommandRequest;
};

export function trimWrappedQuotes(value: string): string {
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

export function tokenizeCommandArgs(input: string): string[] {
  const matches = input.match(/"[^"]*"|'[^']*'|\S+/g) ?? [];
  return matches
    .map((token) => trimWrappedQuotes(token).trim())
    .filter(Boolean);
}

export function parseReviewCommandArgs(
  args?: string,
): ReviewSelection | { error: string } | undefined {
  const tokens = tokenizeCommandArgs(args ?? "");
  if (tokens.length === 0) return undefined;

  const [command, ...rest] = tokens;
  const normalized = command?.toLowerCase();

  if (normalized === "help" || normalized === "--help" || normalized === "-h") {
    return { error: REVIEW_COMMAND_USAGE };
  }

  if (normalized === "uncommitted") {
    if (rest.length > 0) return { error: REVIEW_COMMAND_USAGE };
    return {
      label: "uncommitted changes",
      request: { target: { type: "uncommitted" } },
    };
  }

  if (normalized === "staged") {
    if (rest.length > 0) return { error: REVIEW_COMMAND_USAGE };
    return {
      label: "staged changes",
      request: { target: { type: "staged" } },
    };
  }

  if (normalized === "branch" || normalized === "base") {
    const branch = rest.join(" ").trim();
    if (!branch) return { error: REVIEW_COMMAND_USAGE };
    return {
      label: `base branch ${branch}`,
      request: { target: { type: "baseBranch", branch } },
    };
  }

  return { error: REVIEW_COMMAND_USAGE };
}

export function filterRuns(
  workflow: SubagentWorkflow,
  activeRuns: Map<string, SubagentRunState>,
  recentRuns: SubagentRunState[],
): SubagentRunState[] {
  return [...activeRuns.values(), ...recentRuns].filter(
    (run) => run.workflow === workflow,
  );
}

export function getAllRuns(
  activeRuns: Map<string, SubagentRunState>,
  recentRuns: SubagentRunState[],
): SubagentRunState[] {
  return [...activeRuns.values(), ...recentRuns];
}

export function findTaskById(
  query: string,
  activeRuns: Map<string, SubagentRunState>,
  recentRuns: SubagentRunState[],
):
  | { run: SubagentRunState; task: SubagentRunState["tasks"][number] }
  | { error: string } {
  const trimmed = query.trim();
  if (!trimmed) return { error: "Usage: /subagent <task-id>" };

  const matches = getAllRuns(activeRuns, recentRuns)
    .flatMap((run) => run.tasks.map((task) => ({ run, task })))
    .filter(
      ({ task }) =>
        task.taskId === trimmed ||
        shortTaskId(task.taskId) === trimmed ||
        task.taskId.startsWith(trimmed),
    );

  if (matches.length === 0) {
    return { error: `No subagent found for id: ${trimmed}` };
  }
  if (matches.length > 1) {
    const ids = matches
      .slice(0, 8)
      .map(({ task }) => shortTaskId(task.taskId))
      .join(", ");
    return { error: `Ambiguous subagent id: ${trimmed}. Matches: ${ids}` };
  }

  const [match] = matches;
  return match!;
}
