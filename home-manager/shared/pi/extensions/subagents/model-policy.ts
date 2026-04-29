import {
	COPILOT_PROVIDER,
	type ExploreIntent,
	type SubagentThinkingLevel,
} from "./types.js";

function copilotModel<const T extends string>(
	id: T,
): `${typeof COPILOT_PROVIDER}/${T}` {
	return `${COPILOT_PROVIDER}/${id}` as `${typeof COPILOT_PROVIDER}/${T}`;
}

export const SUBAGENT_MODEL_IDS = {
	claudeOpus: "claude-opus-4.6",
	claudeSonnet: "claude-sonnet-4.6",
	geminiPro: "gemini-3.1-pro-preview",
	fastExplore: "gpt-5.4-mini",
	defaultExplore: "gpt-5.5",
} as const;

export const SUBAGENT_MODELS = {
	claudeOpus: copilotModel(SUBAGENT_MODEL_IDS.claudeOpus),
	claudeSonnet: copilotModel(SUBAGENT_MODEL_IDS.claudeSonnet),
	geminiPro: copilotModel(SUBAGENT_MODEL_IDS.geminiPro),
	fastExplore: copilotModel(SUBAGENT_MODEL_IDS.fastExplore),
	defaultExplore: copilotModel(SUBAGENT_MODEL_IDS.defaultExplore),
} as const;

export const ALLOWED_SUBAGENT_MODELS = [
	SUBAGENT_MODELS.claudeOpus,
	SUBAGENT_MODELS.claudeSonnet,
	SUBAGENT_MODELS.geminiPro,
	SUBAGENT_MODELS.fastExplore,
	SUBAGENT_MODELS.defaultExplore,
] as const;

export type AllowedSubagentModel = (typeof ALLOWED_SUBAGENT_MODELS)[number];

export const FAST_EXPLORE_MODEL: AllowedSubagentModel =
	SUBAGENT_MODELS.fastExplore;
export const DEFAULT_EXPLORE_MODEL: AllowedSubagentModel =
	SUBAGENT_MODELS.defaultExplore;

export const ALLOWED_EXPLORE_INTENTS = ["fast", "balanced", "deep"] as const;
export const DEFAULT_EXPLORE_INTENT: ExploreIntent = "balanced";

export type ExploreExecutionProfile = {
	intent: ExploreIntent;
	model: AllowedSubagentModel;
	thinkingLevel: SubagentThinkingLevel;
};

export const EXPLORE_INTENT_PROFILES: Readonly<
	Record<ExploreIntent, ExploreExecutionProfile>
> = {
	fast: {
		intent: "fast",
		model: FAST_EXPLORE_MODEL,
		thinkingLevel: "medium",
	},
	balanced: {
		intent: "balanced",
		model: DEFAULT_EXPLORE_MODEL,
		thinkingLevel: "medium",
	},
	deep: {
		intent: "deep",
		model: DEFAULT_EXPLORE_MODEL,
		thinkingLevel: "high",
	},
} as const;

export function normalizeExploreIntent(intent: string | undefined): ExploreIntent {
	const normalized = intent?.trim().toLowerCase();
	if (normalized === "fast" || normalized === "balanced" || normalized === "deep") {
		return normalized;
	}
	return DEFAULT_EXPLORE_INTENT;
}

export function resolveExploreExecutionProfile(
	intent: string | undefined,
): ExploreExecutionProfile {
	return EXPLORE_INTENT_PROFILES[normalizeExploreIntent(intent)];
}

export type ReviewerConfig = {
	label: string;
	model: AllowedSubagentModel;
	focus: string;
	thinkingLevel?: SubagentThinkingLevel;
	maxDiffChars?: number;
};

export const FIXED_REVIEWERS: readonly ReviewerConfig[] = [
	{
		label: "Opus 4.6",
		model: SUBAGENT_MODELS.claudeOpus,
		focus: "correctness, regressions, hidden bugs, and edge cases",
		thinkingLevel: "high",
		maxDiffChars: 50_000,
	},
	{
		label: "Gemini 3.1",
		model: SUBAGENT_MODELS.geminiPro,
		focus: "maintainability, clarity, test gaps, and surprising behavior",
		thinkingLevel: "high",
		maxDiffChars: 24_000,
	},
] as const;

export function isAllowedSubagentModel(
	model: string,
): model is AllowedSubagentModel {
	return (ALLOWED_SUBAGENT_MODELS as readonly string[]).includes(model);
}
