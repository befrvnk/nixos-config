import assert from "node:assert/strict";
import test from "node:test";
import { buildExploreTaskInputs, findRunOrThrow } from "./tool-validation.ts";
import type { SubagentRunState } from "./types.ts";

const sampleRun: SubagentRunState = {
  workflow: "explore",
  runId: "run-1",
  mode: "single",
  state: "success",
  startedAt: 1,
  tasks: [],
};

test("findRunOrThrow enforces run ids for status lookups", () => {
  assert.throws(() => findRunOrThrow([], undefined), /requires runId/);
  assert.throws(() => findRunOrThrow([], "missing"), /Run not found: missing/);
  assert.equal(findRunOrThrow([sampleRun], " run-1 "), sampleRun);
});

test("buildExploreTaskInputs validates exactly one task mode and non-empty tasks", () => {
  assert.throws(
    () => buildExploreTaskInputs({}, "/repo"),
    /Provide exactly one of: task or tasks/,
  );
  assert.throws(
    () =>
      buildExploreTaskInputs(
        { task: "inspect", tasks: [{ task: "also inspect" }] },
        "/repo",
      ),
    /Provide exactly one of: task or tasks/,
  );
  assert.throws(
    () => buildExploreTaskInputs({ tasks: [{ task: "   " }] }, "/repo"),
    /All exploration tasks must be non-empty/,
  );
});

test("buildExploreTaskInputs returns normalized single-task inputs", () => {
  const [task] = buildExploreTaskInputs({ task: "Inspect docs" }, "/repo");
  assert.equal(task.task, "Inspect docs");
  assert.equal(task.label, "Inspect docs");
  assert.equal(task.cwd, "/repo");
  assert.equal(task.intent, "balanced");
});
