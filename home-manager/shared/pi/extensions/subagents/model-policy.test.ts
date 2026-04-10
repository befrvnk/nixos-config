import test from "node:test";
import assert from "node:assert/strict";
import {
  ALLOWED_SUBAGENT_MODELS,
  DEFAULT_EXPLORE_MODEL,
  DEFAULT_EXPLORE_THINKING_LEVEL,
  FIXED_REVIEWERS,
  isAllowedSubagentModel,
} from "./model-policy.ts";

test("default explore configuration stays within the allowed model policy", () => {
  assert.ok(ALLOWED_SUBAGENT_MODELS.includes(DEFAULT_EXPLORE_MODEL));
  assert.equal(DEFAULT_EXPLORE_THINKING_LEVEL, "medium");
});

test("fixed reviewers only use allowed models", () => {
  for (const reviewer of FIXED_REVIEWERS) {
    assert.ok(isAllowedSubagentModel(reviewer.model), reviewer.model);
  }
});

test("isAllowedSubagentModel accepts approved models and rejects everything else", () => {
  assert.equal(isAllowedSubagentModel(ALLOWED_SUBAGENT_MODELS[0]!), true);
  assert.equal(isAllowedSubagentModel("github-copilot/not-a-real-model"), false);
  assert.equal(isAllowedSubagentModel("anthropic/claude-sonnet-4"), false);
});
