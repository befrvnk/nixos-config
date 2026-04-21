import test from "node:test";
import assert from "node:assert/strict";
import { buildReviewConsensus } from "./consensus.ts";
import type { SubagentTaskResult } from "../../types.ts";

const baseResult: SubagentTaskResult = {
	taskId: "sub_now_abc123_task_1",
	task: "Review changes",
	status: "success",
	summary: "Looks good.",
	parseMeta: { structure: "valid", missingSections: [], warnings: [] },
};

test("buildReviewConsensus deduplicates findings, callouts, and fix queue items", () => {
	const results: SubagentTaskResult[] = [
		{
			...baseResult,
			data: {
				verdict: "needs attention",
				findings: [
					"[severity: low][confidence: high][path: src/a.ts:1] low issue | evidence | recommendation",
					"[severity: high][confidence: high][path: src/b.ts:2] high issue | evidence | recommendation",
				],
				humanReviewerCallouts: [
					"**This change changes configuration defaults:** src/a.ts",
				],
				suggestedNextSteps: ["Add a regression test", "Update docs"],
			},
		},
		{
			...baseResult,
			taskId: "sub_now_def456_task_2",
			data: {
				verdict: "correct",
				findings: [
					"[severity: high][confidence: high][path: src/b.ts:2] high issue | evidence | recommendation",
				],
				humanReviewerCallouts: [
					"**This change changes configuration defaults:** src/a.ts",
					"**This change introduces a new dependency:** package.json",
				],
				suggestedNextSteps: ["Update docs"],
			},
		},
	];

	assert.deepEqual(buildReviewConsensus(results), {
		verdict: "needs attention",
		findings: [
			"[severity: high][confidence: high][path: src/b.ts:2] high issue | evidence | recommendation",
			"[severity: low][confidence: high][path: src/a.ts:1] low issue | evidence | recommendation",
		],
		humanReviewerCallouts: [
			"**This change changes configuration defaults:** src/a.ts",
			"**This change introduces a new dependency:** package.json",
		],
		suggestedFixQueue: ["Add a regression test", "Update docs"],
		rationale: "2 actionable finding(s) were parsed from reviewer output.",
		reviewerOutputQuality: { valid: 2, partial: 0, invalid: 0, failed: 0 },
		reviewerAgreement: [
			"1 actionable finding(s) were independently flagged by multiple reviewers.",
			"1 actionable finding(s) were raised by only one reviewer.",
			"1 non-blocking callout(s) were shared across reviewers.",
			"1 non-blocking callout(s) were raised by only one reviewer.",
		],
	});
});

test("buildReviewConsensus returns correct when no findings require attention", () => {
	const results: SubagentTaskResult[] = [
		{
			...baseResult,
			data: {
				verdict: "correct",
				findings: [],
				humanReviewerCallouts: [],
				suggestedNextSteps: [],
			},
		},
	];

	assert.deepEqual(buildReviewConsensus(results), {
		verdict: "correct",
		findings: [],
		humanReviewerCallouts: [],
		suggestedFixQueue: [],
		rationale:
			"All reviewer outputs were structured and no actionable findings were reported.",
		reviewerOutputQuality: { valid: 1, partial: 0, invalid: 0, failed: 0 },
		reviewerAgreement: [
			"No actionable findings were flagged by any reviewer.",
			"No non-blocking callouts were raised.",
		],
	});
});

test("buildReviewConsensus returns inconclusive when output quality is mixed without findings", () => {
	const results: SubagentTaskResult[] = [
		{
			...baseResult,
			data: {
				verdict: "correct",
				findings: [],
				humanReviewerCallouts: [],
				suggestedNextSteps: [],
			},
		},
		{
			...baseResult,
			taskId: "sub_now_def456_task_2",
			summary: "",
			parseMeta: {
				structure: "invalid",
				missingSections: ["Verdict"],
				warnings: ["Output contains XML-like or tool-trace content."],
			},
			data: {
				findings: [],
				humanReviewerCallouts: [],
				suggestedNextSteps: [],
			},
		},
	];

	assert.deepEqual(buildReviewConsensus(results), {
		verdict: "inconclusive",
		findings: [],
		humanReviewerCallouts: [],
		suggestedFixQueue: [],
		rationale:
			"Reviewer output quality was mixed (1 valid, 1 invalid), so the review is preserved below but the consensus is inconclusive.",
		reviewerOutputQuality: { valid: 1, partial: 0, invalid: 1, failed: 0 },
		reviewerAgreement: [
			"No actionable findings were flagged by any reviewer.",
			"No non-blocking callouts were raised.",
		],
	});
});
