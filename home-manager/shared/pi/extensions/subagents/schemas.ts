import { StringEnum } from "@mariozechner/pi-ai";
import { Type } from "@sinclair/typebox";
import { MAX_PARALLEL_TASKS } from "./types.js";

export const exploreTaskSchema = Type.Object({
  task: Type.String({ description: "Exploration task to run in an isolated subagent." }),
  model: Type.Optional(Type.String({ description: "Optional GitHub Copilot model override. Defaults to the current GitHub Copilot session model." })),
  cwd: Type.Optional(Type.String({ description: "Optional working directory override for this task." })),
});

export const exploreParamsSchema = Type.Object({
  task: Type.Optional(Type.String({ description: "Single exploration task." })),
  model: Type.Optional(Type.String({ description: "Optional GitHub Copilot model override for single-task mode." })),
  cwd: Type.Optional(Type.String({ description: "Optional working directory override for single-task mode." })),
  tasks: Type.Optional(
    Type.Array(exploreTaskSchema, {
      description: "Parallel exploration tasks. Keep them independent so they can run concurrently.",
      minItems: 1,
      maxItems: MAX_PARALLEL_TASKS,
    }),
  ),
});

export const statusSchema = Type.Object({
  action: StringEnum(["list", "get"] as const, {
    description: 'Either "list" to show active and recent runs, or "get" to inspect one run.',
  }),
  runId: Type.Optional(Type.String({ description: 'Run id for action="get".' })),
});

export const reviewReviewerSchema = Type.Object({
  label: Type.Optional(Type.String({ description: "Optional display label for this reviewer." })),
  model: Type.String({ description: "GitHub Copilot model to run for this reviewer." }),
  focus: Type.Optional(Type.String({ description: "Optional review focus area for this reviewer." })),
});

export const reviewParamsSchema = Type.Object({
  prompt: Type.Optional(Type.String({ description: "Optional extra review instructions to apply to every reviewer." })),
  cwd: Type.Optional(Type.String({ description: "Working directory. Must be inside the repository to review." })),
  target: Type.Optional(
    StringEnum(["working-tree", "staged"] as const, {
      description: 'What to review. "working-tree" compares current changes against baseRef. "staged" reviews only staged changes.',
      default: "working-tree",
    }),
  ),
  baseRef: Type.Optional(Type.String({ description: 'Base ref to diff against. Defaults to "HEAD".' })),
  files: Type.Optional(
    Type.Array(Type.String(), {
      description: "Optional file subset to review.",
      minItems: 1,
      maxItems: 100,
    }),
  ),
  reviewers: Type.Optional(
    Type.Array(reviewReviewerSchema, {
      description: "Parallel review subagents to run. Defaults to Opus 4.6 and Gemini 3.1 on GitHub Copilot.",
      minItems: 1,
      maxItems: MAX_PARALLEL_TASKS,
    }),
  ),
});
