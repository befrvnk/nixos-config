import test from "node:test";
import assert from "node:assert/strict";
import {
  formatDuration,
  parseBullets,
  renderRunMarkdown,
  renderTaskHistoryMarkdown,
  shortTaskId,
  splitMarkdownSections,
  uniqueNonEmptyStrings,
} from "./formatting.ts";
import type { SubagentRunState, SubagentTaskState } from "./types.ts";

test("formatDuration renders milliseconds, seconds, and minutes", () => {
  assert.equal(formatDuration(0, 250), "250ms");
  assert.equal(formatDuration(0, 1500), "1.5s");
  assert.equal(formatDuration(0, 62_000), "1m2s");
});

test("splitMarkdownSections preserves preamble as summary and parseBullets extracts list items", () => {
  const sections = splitMarkdownSections(
    "Preamble\n\n## Findings\n- one\n- two\n\n## Next Steps\n- three",
  );

  assert.equal(sections.get("summary"), "Preamble");
  assert.deepEqual(parseBullets(sections.get("findings")), ["one", "two"]);
  assert.deepEqual(parseBullets(undefined), undefined);
});

test("uniqueNonEmptyStrings trims, deduplicates, and drops blanks", () => {
  assert.deepEqual(uniqueNonEmptyStrings([" one ", "", "one", "two "]), [
    "one",
    "two",
  ]);
});

test("shortTaskId prefers compact ids for generated subagent ids", () => {
  assert.equal(shortTaskId("sub_now_abc123_task_2"), "abc123/2");
  assert.equal(shortTaskId("plain-id-1234567890"), "-id-1234567890");
});

test("renderTaskHistoryMarkdown and renderRunMarkdown include key run details", () => {
  const task: SubagentTaskState = {
    workflow: "explore",
    index: 0,
    taskId: "sub_now_abc123_task_1",
    task: "Investigate prompt flow",
    label: "Prompt flow",
    intent: "balanced",
    model: "github-copilot/gpt-5.4-mini",
    thinkingLevel: "medium",
    cwd: "/tmp/project",
    state: "success",
    currentTool: undefined,
    toolUses: 2,
    turnCount: 1,
    tokenCount: 1200,
    responseText: "summary",
    progressItems: [{ text: "Inspect files", done: true }],
    history: [
      { timestamp: 0, kind: "lifecycle", text: "started" },
      { timestamp: 1000, kind: "assistant", text: "done" },
    ],
    recentTools: ["read src/index.ts"],
    recentOutputLines: ["Found file"],
    summary: "Everything looks good.",
    data: { key: true },
    startedAt: 0,
    endedAt: 1500,
  };

  const run: SubagentRunState = {
    workflow: "explore",
    runId: "sub_now_abc123",
    mode: "single",
    state: "success",
    startedAt: 0,
    endedAt: 1500,
    tasks: [task],
  };

  const taskMarkdown = renderTaskHistoryMarkdown(task, run);
  assert.match(taskMarkdown, /# Subagent abc123\/1/);
  assert.match(taskMarkdown, /- Intent: balanced/);
  assert.match(taskMarkdown, /## Summary/);
  assert.match(taskMarkdown, /Everything looks good\./);

  const runMarkdown = renderRunMarkdown(run);
  assert.match(runMarkdown, /# Explore sub_now_abc123/);
  assert.match(runMarkdown, /- Intent: balanced/);
  assert.match(runMarkdown, /- Tool uses: 2/);
  assert.match(runMarkdown, /- Progress:/);
});
