import test from "node:test";
import assert from "node:assert/strict";
import { describeTaskExecutionProfile } from "./task-profile.ts";

test("describeTaskExecutionProfile renders compact intent, model, and thinking details", () => {
  assert.equal(
    describeTaskExecutionProfile({
      intent: "fast",
      model: "github-copilot/gpt-5.4-mini",
      thinkingLevel: "medium",
    }),
    "fast · gpt-5.4-mini · medium",
  );

  assert.equal(
    describeTaskExecutionProfile({
      model: "github-copilot/gpt-5.4",
      thinkingLevel: "high",
    }),
    "gpt-5.4 · high",
  );

  assert.equal(describeTaskExecutionProfile({}), "");
});
