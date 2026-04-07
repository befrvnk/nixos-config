import { Type } from "@sinclair/typebox";
import { MAX_PARALLEL_TASKS } from "./types.js";

export const exploreTaskSchema = Type.Object({
  task: Type.String({ description: "Exploration task to run in an isolated subagent." }),
  model: Type.Optional(Type.String({ description: "Optional model override. Defaults to the parent session model." })),
  cwd: Type.Optional(Type.String({ description: "Optional working directory override for this task." })),
});

export const exploreParamsSchema = Type.Object({
  task: Type.Optional(Type.String({ description: "Single exploration task." })),
  model: Type.Optional(Type.String({ description: "Optional model override for single-task mode." })),
  cwd: Type.Optional(Type.String({ description: "Optional working directory override for single-task mode." })),
  tasks: Type.Optional(
    Type.Array(exploreTaskSchema, {
      description: "Parallel exploration tasks. Keep them independent so they can run concurrently.",
      minItems: 1,
      maxItems: MAX_PARALLEL_TASKS,
    }),
  ),
});

export const exploreStatusSchema = Type.Object({
  action: Type.String({ description: 'Either "list" to show active and recent runs, or "get" to inspect one run.' }),
  runId: Type.Optional(Type.String({ description: 'Run id for action="get".' })),
});
