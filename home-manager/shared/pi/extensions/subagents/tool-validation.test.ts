import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  buildExploreTaskInputs,
  findRunOrThrow,
  resolveExploreCwd,
} from "./tool-validation.ts";
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

test("resolveExploreCwd supports relative and @-prefixed paths", () => {
  const repoRoot = fs.mkdtempSync(path.join(os.tmpdir(), "subagent-cwd-"));
  const nested = path.join(repoRoot, "docs", "guide");
  fs.mkdirSync(nested, { recursive: true });

  assert.equal(resolveExploreCwd("docs/guide", repoRoot), fs.realpathSync.native(nested));
  assert.equal(resolveExploreCwd("@docs/guide", repoRoot), fs.realpathSync.native(nested));
  assert.equal(resolveExploreCwd(`@${nested}`, repoRoot), fs.realpathSync.native(nested));
  assert.throws(
    () => resolveExploreCwd("missing-dir", repoRoot),
    /Exploration cwd does not exist/,
  );
});
