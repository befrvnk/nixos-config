import {
  DEFAULT_EXPLORE_INTENT,
  resolveExploreExecutionProfile,
} from "./model-policy.js";
import type {
  SubagentRunState,
  SubagentTaskInput,
} from "./types.js";

export function findRunOrThrow(
  runs: SubagentRunState[],
  runId: string | undefined,
): SubagentRunState {
  const trimmedRunId = runId?.trim();
  if (!trimmedRunId) {
    throw new Error('action="get" requires runId.');
  }

  const run = runs.find((candidate) => candidate.runId === trimmedRunId);
  if (!run) {
    throw new Error(`Run not found: ${trimmedRunId}`);
  }

  return run;
}

type ExploreParams = {
  task?: string;
  intent?: string;
  cwd?: string;
  tasks?: Array<{ task: string; intent?: string; cwd?: string }>;
};

export function buildExploreTaskInputs(
  params: ExploreParams,
  defaultCwd: string,
): SubagentTaskInput[] {
  const hasSingle = typeof params.task === "string" && params.task.trim().length > 0;
  const hasParallel = Array.isArray(params.tasks) && params.tasks.length > 0;

  if (Number(hasSingle) + Number(hasParallel) !== 1) {
    throw new Error("Provide exactly one of: task or tasks.");
  }

  const defaultIntent = params.intent?.trim() || DEFAULT_EXPLORE_INTENT;
  const tasks: SubagentTaskInput[] = hasSingle
    ? (() => {
        const taskText = params.task?.trim() ?? "";
        const profile = resolveExploreExecutionProfile(defaultIntent);
        return [
          {
            task: taskText,
            label: taskText,
            intent: profile.intent,
            model: profile.model,
            thinkingLevel: profile.thinkingLevel,
            cwd: params.cwd?.trim() || defaultCwd,
          },
        ];
      })()
    : (params.tasks ?? []).map((task) => {
        const profile = resolveExploreExecutionProfile(task.intent ?? defaultIntent);
        return {
          task: task.task.trim(),
          label: task.task.trim(),
          intent: profile.intent,
          model: profile.model,
          thinkingLevel: profile.thinkingLevel,
          cwd: task.cwd?.trim() || defaultCwd,
        };
      });

  if (tasks.some((task) => !task.task)) {
    throw new Error("All exploration tasks must be non-empty.");
  }

  return tasks;
}
