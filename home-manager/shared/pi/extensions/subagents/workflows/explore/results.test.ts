import test from "node:test";
import assert from "node:assert/strict";
import {
  parseExploreOutput,
  renderFinalExploreResults,
  summarizeExploreResult,
} from "./results.ts";
import type { SubagentTaskResult } from "../../types.ts";

const result: SubagentTaskResult = {
  taskId: "sub_now_abc123_task_1",
  task: "Inspect docs",
  label: "Docs",
  intent: "balanced",
  model: "github-copilot/gpt-5.4-mini",
  thinkingLevel: "medium",
  cwd: "/tmp/project",
  status: "success",
  summary: "The docs are up to date.",
  data: {
    sources: ["README.md", "docs/usage.md"],
    keyFindings: ["README and docs agree"],
    suggestedNextSteps: [],
  },
};

test("parseExploreOutput extracts summary sections and normalizes placeholder bullets away", () => {
  const parsed = parseExploreOutput([
    "## Summary",
    "Investigated the repo.",
    "",
    "## Sources",
    "- README.md",
    "",
    "## Key Findings",
    "- Found the feature flag",
    "",
    "## Next Steps",
    "- None",
  ].join("\n"));

  assert.equal(parsed.summary, "Investigated the repo.");
  assert.deepEqual(parsed.data, {
    sources: ["README.md"],
    keyFindings: ["Found the feature flag"],
    suggestedNextSteps: undefined,
  });
});

test("summarizeExploreResult prefers key findings, then summary, then error", () => {
  assert.equal(summarizeExploreResult(result), "README and docs agree");
  assert.equal(
    summarizeExploreResult({ ...result, data: {}, summary: "Single line summary" }),
    "Single line summary",
  );
  assert.equal(
    summarizeExploreResult({ ...result, data: {}, summary: "", error: "something failed" }),
    "something failed",
  );
});

test("renderFinalExploreResults includes defaults for empty sections and errors", () => {
  const markdown = renderFinalExploreResults("run-1", "single", [
    result,
    {
      ...result,
      taskId: "sub_now_def456_task_2",
      label: "Broken task",
      status: "error",
      summary: "",
      data: {},
      error: "Timed out",
    },
  ]);

  assert.match(markdown, /# Exploration Results/);
  assert.match(markdown, /## Task 1/);
  assert.match(markdown, /- Intent: balanced/);
  assert.match(markdown, /- README\.md/);
  assert.match(markdown, /## Task 2/);
  assert.match(markdown, /No summary returned\./);
  assert.match(markdown, /### Error\nTimed out/);
  assert.match(markdown, /### Next Steps\n- None/);
});
