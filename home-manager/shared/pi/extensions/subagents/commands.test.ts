import test from "node:test";
import assert from "node:assert/strict";
import {
  findTaskById,
  parseReviewCommandArgs,
  REVIEW_COMMAND_USAGE,
  tokenizeCommandArgs,
} from "./commands.ts";
import type { SubagentRunState } from "./types.ts";

function makeRun(taskId: string, label: string): SubagentRunState {
  return {
    workflow: "explore",
    runId: `run-${label}`,
    mode: "single",
    state: "success",
    startedAt: 0,
    endedAt: 1000,
    tasks: [
      {
        workflow: "explore",
        index: 0,
        taskId,
        task: label,
        label,
        state: "success",
        toolUses: 0,
        turnCount: 0,
        tokenCount: 0,
        responseText: "",
        history: [],
        recentTools: [],
        recentOutputLines: [],
      },
    ],
  };
}

test("tokenizeCommandArgs preserves quoted segments", () => {
  assert.deepEqual(tokenizeCommandArgs("branch 'feature/foo bar'"), [
    "branch",
    "feature/foo bar",
  ]);
  assert.deepEqual(tokenizeCommandArgs('base "origin/main"'), [
    "base",
    "origin/main",
  ]);
});

test("parseReviewCommandArgs supports uncommitted, staged, and branch targets", () => {
  assert.equal(parseReviewCommandArgs(undefined), undefined);
  assert.deepEqual(parseReviewCommandArgs("uncommitted"), {
    label: "uncommitted changes",
    request: { target: { type: "uncommitted" } },
  });
  assert.deepEqual(parseReviewCommandArgs("staged"), {
    label: "staged changes",
    request: { target: { type: "staged" } },
  });
  assert.deepEqual(parseReviewCommandArgs("branch origin/main"), {
    label: "base branch origin/main",
    request: { target: { type: "baseBranch", branch: "origin/main" } },
  });
});

test("parseReviewCommandArgs returns usage for invalid invocations", () => {
  assert.deepEqual(parseReviewCommandArgs("help"), { error: REVIEW_COMMAND_USAGE });
  assert.deepEqual(parseReviewCommandArgs("branch"), { error: REVIEW_COMMAND_USAGE });
  assert.deepEqual(parseReviewCommandArgs("wat"), { error: REVIEW_COMMAND_USAGE });
});

test("findTaskById matches exact ids and compact ids", () => {
  const active = new Map<string, SubagentRunState>([
    ["run-one", makeRun("sub_now_abc123_task_1", "one")],
  ]);

  const exact = findTaskById("sub_now_abc123_task_1", active, []);
  assert.equal("error" in exact, false);
  if (!("error" in exact)) {
    assert.equal(exact.task.label, "one");
  }

  const compact = findTaskById("abc123/1", active, []);
  assert.equal("error" in compact, false);
  if (!("error" in compact)) {
    assert.equal(compact.task.label, "one");
  }
});

test("findTaskById reports missing and ambiguous matches", () => {
  const active = new Map<string, SubagentRunState>([
    ["run-one", makeRun("sub_now_abc123_task_1", "one")],
  ]);
  const recent = [makeRun("sub_then_abc999_task_2", "two")];

  assert.deepEqual(findTaskById("", active, recent), {
    error: "Usage: /subagent <task-id>",
  });
  assert.deepEqual(findTaskById("missing", active, recent), {
    error: "No subagent found for id: missing",
  });

  const ambiguous = findTaskById("sub_", active, recent);
  assert.equal("error" in ambiguous, true);
  if ("error" in ambiguous) {
    assert.match(ambiguous.error, /Ambiguous subagent id/);
  }
});
