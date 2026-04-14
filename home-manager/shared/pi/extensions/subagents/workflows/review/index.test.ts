import test from "node:test";
import assert from "node:assert/strict";
import {
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
  assert.match(task, /Additional review instructions:\nPrioritize database changes\./);
  assert.match(task, /## Verdict/);
  assert.match(task, /## Human Reviewer Callouts/);
  assert.match(task, /Changed files:\n- src\/index\.ts/);
  assert.match(task, /\[diff truncated for reviewer prompt budget\]/);
});

test("parseReviewOutput normalizes None bullets away from structured findings", () => {
  const parsed = parseReviewOutput([
    "## Summary",
    "Looks safe overall.",
    "",
    "## Verdict",
    "correct",
    "",
    "## Findings",
    "- None",
    "",
    "## Human Reviewer Callouts",
    "- None",
    "",
    "## Next Steps",
    "- Add a regression test",
  ].join("\n"));

  assert.equal(parsed.summary, "Looks safe overall.");
  assert.deepEqual(parsed.data, {
    verdict: "correct",
    findings: [],
    humanReviewerCallouts: [],
    suggestedNextSteps: ["Add a regression test"],
  });
});

test("renderFinalReviewResults includes reviewer metadata, findings, and context", () => {
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
      metadata: { focus: reviewer.focus },
    },
    {
      taskId: "sub_now_def456_task_2",
      task: "Review changes",
      label: "Gemini 3.1",
      model: "github-copilot/gemini-3.1-pro-preview",
      status: "error",
      summary: "",
      data: { verdict: "correct", findings: [], humanReviewerCallouts: [] },
      error: "Timed out",
    },
  ];

  const markdown = renderFinalReviewResults("run-1", "parallel", results, context);
  assert.match(markdown, /# Review Results/);
  assert.match(markdown, /- Target: uncommitted changes/);
  assert.match(markdown, /- Focus: correctness and regressions/);
  assert.match(markdown, /### Verdict\nneeds attention/);
  assert.match(markdown, /Human Reviewer Callouts/);
  assert.match(markdown, /This change changes configuration defaults/);
  assert.match(markdown, /Add a unit test/);
  assert.match(markdown, /### Error\nTimed out/);
});
