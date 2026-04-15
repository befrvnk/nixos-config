import test from "node:test";
import assert from "node:assert/strict";
import {
  ALLOWED_EXPLORE_INTENTS,
  ALLOWED_SUBAGENT_MODELS,
  DEFAULT_EXPLORE_INTENT,
  EXPLORE_INTENT_PROFILES,
  FIXED_REVIEWERS,
  isAllowedSubagentModel,
  normalizeExploreIntent,
  resolveExploreExecutionProfile,
} from "./model-policy.ts";

test("default explore configuration stays within the allowed model policy", () => {
  const profile = resolveExploreExecutionProfile(undefined);
  assert.equal(profile.intent, DEFAULT_EXPLORE_INTENT);
  assert.ok(ALLOWED_SUBAGENT_MODELS.includes(profile.model));
  assert.equal(profile.thinkingLevel, "medium");
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

test("explore intent normalization and profile resolution are safe by default", () => {
  assert.deepEqual(ALLOWED_EXPLORE_INTENTS, ["fast", "balanced", "deep"]);
  assert.equal(normalizeExploreIntent(undefined), "balanced");
  assert.equal(normalizeExploreIntent("FAST"), "fast");
  assert.equal(normalizeExploreIntent("unknown"), "balanced");

  assert.deepEqual(resolveExploreExecutionProfile("fast"), EXPLORE_INTENT_PROFILES.fast);
  assert.deepEqual(resolveExploreExecutionProfile("balanced"), EXPLORE_INTENT_PROFILES.balanced);
  assert.deepEqual(resolveExploreExecutionProfile("deep"), EXPLORE_INTENT_PROFILES.deep);
  assert.deepEqual(resolveExploreExecutionProfile("wrong"), EXPLORE_INTENT_PROFILES.balanced);

  assert.deepEqual(EXPLORE_INTENT_PROFILES.fast, {
    intent: "fast",
    model: "github-copilot/gpt-5.4-mini",
    thinkingLevel: "medium",
  });
  assert.deepEqual(EXPLORE_INTENT_PROFILES.balanced, {
    intent: "balanced",
    model: "github-copilot/gpt-5.4",
    thinkingLevel: "medium",
  });
  assert.deepEqual(EXPLORE_INTENT_PROFILES.deep, {
    intent: "deep",
    model: "github-copilot/gpt-5.4",
    thinkingLevel: "high",
  });
});
