import test from "node:test";
import assert from "node:assert/strict";
import {
  ALLOWED_SUBAGENT_MODELS,
  FIXED_REVIEWERS,
  isAllowedSubagentModel,
  REVIEW_BRIEF_MODEL,
  SUBAGENT_MODELS,
} from "./model-policy.ts";

test("review models stay within the allowed model policy", () => {
  assert.deepEqual(ALLOWED_SUBAGENT_MODELS, [
    SUBAGENT_MODELS.claudeOpus,
    SUBAGENT_MODELS.geminiPro,
    REVIEW_BRIEF_MODEL,
  ]);

  for (const reviewer of FIXED_REVIEWERS) {
    assert.ok(isAllowedSubagentModel(reviewer.model), reviewer.model);
  }
  assert.ok(isAllowedSubagentModel(REVIEW_BRIEF_MODEL));
});

test("isAllowedSubagentModel accepts approved models and rejects everything else", () => {
  assert.equal(isAllowedSubagentModel(ALLOWED_SUBAGENT_MODELS[0]!), true);
  assert.equal(isAllowedSubagentModel("github-copilot/not-a-real-model"), false);
  assert.equal(isAllowedSubagentModel("anthropic/claude-sonnet-4"), false);
});
