import {
	COPILOT_PROVIDER,
	type SubagentThinkingLevel,
} from "./types.js";

function copilotModel<const T extends string>(
	id: T,
): `${typeof COPILOT_PROVIDER}/${T}` {
	return `${COPILOT_PROVIDER}/${id}` as `${typeof COPILOT_PROVIDER}/${T}`;
}

export const SUBAGENT_MODEL_IDS = {
	claudeOpus: "claude-opus-4.8",
	geminiPro: "gemini-3.1-pro-preview",
	reviewBrief: "gpt-5.6-luna",
} as const;

export const SUBAGENT_MODELS = {
	claudeOpus: copilotModel(SUBAGENT_MODEL_IDS.claudeOpus),
	geminiPro: copilotModel(SUBAGENT_MODEL_IDS.geminiPro),
	reviewBrief: copilotModel(SUBAGENT_MODEL_IDS.reviewBrief),
} as const;

export const ALLOWED_SUBAGENT_MODELS = [
	SUBAGENT_MODELS.claudeOpus,
	SUBAGENT_MODELS.geminiPro,
	SUBAGENT_MODELS.reviewBrief,
] as const;

export type AllowedSubagentModel = (typeof ALLOWED_SUBAGENT_MODELS)[number];

export const REVIEW_BRIEF_MODEL: AllowedSubagentModel =
	SUBAGENT_MODELS.reviewBrief;

export type ReviewerConfig = {
	label: string;
	model: AllowedSubagentModel;
	focus: string;
	thinkingLevel?: SubagentThinkingLevel;
	maxDiffChars?: number;
};

export const FIXED_REVIEWERS: readonly ReviewerConfig[] = [
	{
		label: "Opus 4.8",
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
