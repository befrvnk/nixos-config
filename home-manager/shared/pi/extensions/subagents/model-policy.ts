import { COPILOT_PROVIDER, type SubagentThinkingLevel } from "./types.js";

export const ALLOWED_SUBAGENT_MODELS = [
	`${COPILOT_PROVIDER}/claude-opus-4.6`,
	`${COPILOT_PROVIDER}/claude-sonnet-4.6`,
	`${COPILOT_PROVIDER}/gemini-3.1-pro-preview`,
	`${COPILOT_PROVIDER}/gpt-5.4-mini`,
	`${COPILOT_PROVIDER}/gpt-5.4`,
] as const;

export type AllowedSubagentModel = (typeof ALLOWED_SUBAGENT_MODELS)[number];

export const DEFAULT_EXPLORE_MODEL =
	`${COPILOT_PROVIDER}/gpt-5.4-mini` as AllowedSubagentModel;
export const DEFAULT_EXPLORE_THINKING_LEVEL: SubagentThinkingLevel =
	"medium";

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
		model: `${COPILOT_PROVIDER}/claude-opus-4.6` as AllowedSubagentModel,
		focus: "correctness, regressions, hidden bugs, and edge cases",
		thinkingLevel: "high",
		maxDiffChars: 50_000,
	},
	{
		label: "Gemini 3.1",
		model: `${COPILOT_PROVIDER}/gemini-3.1-pro-preview` as AllowedSubagentModel,
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
