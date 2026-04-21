import test from "node:test";
import assert from "node:assert/strict";
import {
	buildReviewRepairPrompt,
	buildReviewTask,
	parseReviewOutput,
	renderFinalReviewResults,
	type ReviewContext,
} from "./index.ts";
import type { ReviewerConfig } from "../../model-policy.ts";
import type { SubagentTaskResult } from "../../types.ts";

const context: ReviewContext = {
	repoRoot: "/tmp/project",
	target: "uncommitted changes",
	baseRef: "HEAD",
	statusShort: " M src/index.ts",
	diffStat: " src/index.ts | 2 +-",
	changedFiles: ["src/index.ts"],
	diffPreview: "diff --git a/src/index.ts b/src/index.ts\n+new line\n-old line",
	diffWasTruncated: false,
};

const reviewer: ReviewerConfig = {
	label: "Opus 4.6",
	model: "github-copilot/claude-opus-4.6",
	focus: "correctness and regressions",
	thinkingLevel: "medium",
	maxDiffChars: 20,
};

test("buildReviewTask includes focus, diff context, and prompt-budget truncation notice", () => {
	const task = buildReviewTask(context, reviewer, "Prioritize database changes.");

	assert.match(task, /Review focus: correctness and regressions/);
	assert.match(
		task,
		/Additional review instructions:\nPrioritize database changes\./,
	);
	assert.match(task, /## Verdict/);
	assert.match(task, /## Non-blocking Callouts/);
	assert.match(task, /Changed files:\n- src\/index\.ts/);
	assert.match(task, /\[diff truncated for reviewer prompt budget\]/);
});

test("parseReviewOutput normalizes None bullets away from structured findings", () => {
	const parsed = parseReviewOutput(
		[
			"## Summary",
			"Looks safe overall.",
			"",
			"## Verdict",
			"correct",
			"",
			"## Findings",
			"- None",
			"",
			"## Non-blocking Callouts",
			"- None",
			"",
			"## Next Steps",
			"- Add a regression test",
		].join("\n"),
	);

	assert.equal(parsed.summary, "Looks safe overall.");
	assert.deepEqual(parsed.data, {
		verdict: "correct",
		findings: [],
		humanReviewerCallouts: [],
		suggestedNextSteps: ["Add a regression test"],
	});
	assert.deepEqual(parsed.parseMeta, {
		structure: "valid",
		missingSections: [],
		warnings: [],
	});
});

test("parseReviewOutput marks narrated structured output partial and excludes the preamble from summary", () => {
	const parsed = parseReviewOutput(
		[
			"Let me inspect the relevant source files for surrounding context.",
			"",
			"<details>",
			"<summary>Reading files</summary>",
			"I checked the surrounding code.",
			"</details>",
			"",
			"## Summary",
			"Looks safe overall.",
			"",
			"## Verdict",
			"correct",
			"",
			"## Findings",
			"- None",
			"",
			"## Non-blocking Callouts",
			"- None",
			"",
			"## Next Steps",
			"- None",
		].join("\n"),
	);

	assert.equal(parsed.summary, "Looks safe overall.");
	assert.equal(parsed.parseMeta?.structure, "partial");
	assert.match(parsed.parseMeta?.warnings?.join("\n") ?? "", /Unexpected preamble/i);
	assert.match(parsed.parseMeta?.warnings?.join("\n") ?? "", /HTML-style disclosure markup/i);
});

test("buildReviewRepairPrompt requests a strict rewrite for malformed output", () => {
	const parsed = parseReviewOutput(
		[
			"Let me inspect the relevant files for context.",
			"",
			"<read_file>",
			"<path>home-manager/shared/pi/extensions/subagents/runner.ts</path>",
			"</read_file>",
		].join("\n"),
	);

	const prompt = buildReviewRepairPrompt(
		parsed,
		[
			"Let me inspect the relevant files for context.",
			"",
			"<read_file>",
		].join("\n"),
	);

	assert.match(prompt ?? "", /did not follow the required review output format/i);
	assert.match(prompt ?? "", /## Non-blocking Callouts/);
	assert.match(prompt ?? "", /Do not include tool narration, XML-like tags/);
	assert.match(prompt ?? "", /Start with `## Summary` on the first non-empty line/);
});

test("parseReviewOutput marks raw tool-trace output invalid and keeps parsed summary empty", () => {
	const parsed = parseReviewOutput(
		[
			"Let me inspect the relevant files for context.",
			"",
			"<read_file>",
			"<path>home-manager/shared/pi/extensions/subagents/runner.ts</path>",
			"</read_file>",
		].join("\n"),
	);

	assert.equal(parsed.summary, "");
	assert.deepEqual(parsed.data, {
		verdict: undefined,
		findings: [],
		humanReviewerCallouts: [],
		suggestedNextSteps: [],
	});
	assert.equal(parsed.parseMeta?.structure, "invalid");
	assert.match(parsed.parseMeta?.warnings?.join("\n") ?? "", /tool-trace/i);
});

test("renderFinalReviewResults preserves malformed raw output, repair metadata, and agreement summary", () => {
	const results: SubagentTaskResult[] = [
		{
			taskId: "sub_now_abc123_task_1",
			task: "Review changes",
			label: "Opus 4.6",
			model: reviewer.model,
			thinkingLevel: "medium",
			cwd: context.repoRoot,
			status: "success",
			summary: "One bug found.",
			data: {
				verdict: "needs attention",
				findings: [
					"[severity: medium][confidence: high][path: src/index.ts:10] issue | evidence | recommendation",
				],
				humanReviewerCallouts: [
					"**This change changes configuration defaults:** src/index.ts",
				],
				suggestedNextSteps: ["Add a unit test"],
			},
			parseMeta: { structure: "valid", missingSections: [], warnings: [] },
			metadata: { focus: reviewer.focus, repairAttempted: true, repairSucceeded: true },
		},
		{
			taskId: "sub_now_def456_task_2",
			task: "Review changes",
			label: "Gemini 3.1",
			model: "github-copilot/gemini-3.1-pro-preview",
			status: "error",
			summary: "",
			data: {
				findings: [],
				humanReviewerCallouts: [],
				suggestedNextSteps: [],
			},
			parseMeta: {
				structure: "invalid",
				missingSections: ["Summary", "Verdict", "Findings"],
				warnings: ["Output contains XML-like or tool-trace content."],
			},
			rawResponse: [
				"Let me inspect the relevant files for context.",
				"",
				"<read_file>",
				"<path>home-manager/shared/pi/extensions/subagents/runner.ts</path>",
				"</read_file>",
			].join("\n"),
			metadata: { repairAttempted: true, repairSucceeded: false },
			error: "Timed out",
		},
	];

	const markdown = renderFinalReviewResults("run-1", "parallel", results, context);
	assert.match(markdown, /# Review Results/);
	assert.match(markdown, /- Target: uncommitted changes/);
	assert.match(markdown, /### Changed Files\n- src\/index\.ts/);
	assert.match(markdown, /## Consensus/);
	assert.match(markdown, /### Rationale/);
	assert.match(markdown, /### Output Quality/);
	assert.match(
		markdown,
		/- Note: failed runs are also counted in the structured-format buckets above\./,
	);
	assert.match(markdown, /### Reviewer Agreement/);
	assert.match(markdown, /No actionable findings were flagged by any reviewer\.|1 actionable finding/);
	assert.match(markdown, /### Suggested Follow-ups\n- Add a unit test/);
	assert.match(markdown, /- Focus: correctness and regressions/);
	assert.match(markdown, /- Formatting repair: succeeded/);
	assert.match(markdown, /- Formatting repair: attempted; output still partial or invalid/);
	assert.match(markdown, /- Structured format: valid/);
	assert.match(markdown, /- Structured format: invalid/);
	assert.match(markdown, /### Structured Verdict\nneeds attention/);
	assert.match(markdown, /Non-blocking Callouts/);
	assert.match(markdown, /This change changes configuration defaults/);
	assert.match(markdown, /### Preserved Raw Output/);
	assert.match(markdown, /```text\nLet me inspect the relevant files for context\./);
	assert.match(markdown, /<read_file>/);
	assert.match(markdown, /### Error\nTimed out/);
});
