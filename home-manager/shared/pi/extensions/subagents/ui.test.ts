import test from "node:test";
import assert from "node:assert/strict";
import { REVIEW_BRIEF_MODEL, SUBAGENT_MODELS } from "./model-policy.ts";
import { describeTaskExecutionProfile } from "./task-profile.ts";

function shortModelName(model: string): string {
  return model.slice(model.indexOf("/") + 1);
}

test("describeTaskExecutionProfile renders compact model and thinking details", () => {
  assert.equal(
    describeTaskExecutionProfile({
      model: REVIEW_BRIEF_MODEL,
      thinkingLevel: "medium",
    }),
    `${shortModelName(REVIEW_BRIEF_MODEL)} · medium`,
  );

  assert.equal(
    describeTaskExecutionProfile({
      model: SUBAGENT_MODELS.claudeOpus,
      thinkingLevel: "high",
    }),
    `${shortModelName(SUBAGENT_MODELS.claudeOpus)} · high`,
  );

  assert.equal(describeTaskExecutionProfile({}), "");
});
