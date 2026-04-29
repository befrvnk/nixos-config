import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_EXPLORE_MODEL, FAST_EXPLORE_MODEL } from "./model-policy.ts";
import { describeTaskExecutionProfile } from "./task-profile.ts";

function shortModelName(model: string): string {
  return model.slice(model.indexOf("/") + 1);
}

test("describeTaskExecutionProfile renders compact intent, model, and thinking details", () => {
  assert.equal(
    describeTaskExecutionProfile({
      intent: "fast",
      model: FAST_EXPLORE_MODEL,
      thinkingLevel: "medium",
    }),
    `fast · ${shortModelName(FAST_EXPLORE_MODEL)} · medium`,
  );

  assert.equal(
    describeTaskExecutionProfile({
      model: DEFAULT_EXPLORE_MODEL,
      thinkingLevel: "high",
    }),
    `${shortModelName(DEFAULT_EXPLORE_MODEL)} · high`,
  );

  assert.equal(describeTaskExecutionProfile({}), "");
});
