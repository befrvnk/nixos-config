import test from "node:test";
import assert from "node:assert/strict";
import { buildReviewConsensus } from "./consensus.ts";
import type { SubagentTaskResult } from "../../types.ts";

const baseResult: SubagentTaskResult = {
	taskId: "sub_now_abc123_task_1",
	task: "Review changes",
	status: "success",
	summary: "Looks good.",
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
	});
});
