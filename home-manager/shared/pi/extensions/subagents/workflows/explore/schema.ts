import { StringEnum } from "@mariozechner/pi-ai";
import { Type } from "@sinclair/typebox";
import { ALLOWED_EXPLORE_INTENTS } from "../../model-policy.js";
import { MAX_LOGICAL_EXPLORE_TASKS } from "../../types.js";

const exploreIntentDescription =
	'Optional exploration intent. The extension maps this to a safe internal model profile. Use "fast" for lightweight scans, "balanced" for the default tradeoff, and "deep" for heavier synthesis. Unknown or omitted intents fall back to "balanced".';

const exploreIntentSchema = StringEnum(ALLOWED_EXPLORE_INTENTS, {
	description: exploreIntentDescription,
});

export const exploreTaskSchema = Type.Object({
	task: Type.String({
		description: "Exploration task to run in an isolated subagent.",
	}),
	intent: Type.Optional(exploreIntentSchema),
	cwd: Type.Optional(
		Type.String({
			description: "Optional working directory override for this task.",
		}),
	),
});

export const exploreParamsSchema = Type.Object({
	task: Type.Optional(Type.String({ description: "Single exploration task." })),
	intent: Type.Optional(
		StringEnum(ALLOWED_EXPLORE_INTENTS, {
			description:
				'Top-level exploration intent. For a single task, it applies to that task. For parallel tasks, it acts as the default intent unless a task overrides it. Unknown or omitted intents fall back to "balanced".',
		}),
	),
	cwd: Type.Optional(
		Type.String({
			description: "Optional working directory override for single-task mode.",
		}),
	),
	tasks: Type.Optional(
		Type.Array(exploreTaskSchema, {
			description:
				"Parallel exploration tasks. Keep them independent so they can run concurrently.",
			minItems: 1,
			maxItems: MAX_LOGICAL_EXPLORE_TASKS,
		}),
	),
});

export const statusSchema = Type.Object({
	action: StringEnum(["list", "get"] as const, {
		description:
			'Either "list" to show active and recent runs, or "get" to inspect one run.',
	}),
	runId: Type.Optional(
		Type.String({ description: 'Run id for action="get".' }),
	),
});
