import test from "node:test";
import assert from "node:assert/strict";
import { buildReviewContextMessage } from "./review-context.ts";

test("buildReviewContextMessage returns undefined for blank input", () => {
	assert.equal(buildReviewContextMessage(""), undefined);
	assert.equal(buildReviewContextMessage("   "), undefined);
});

test("buildReviewContextMessage wraps and trims a review result", () => {
	const prompt = buildReviewContextMessage("\n# Review Results\n- Finding one\n");

	assert.match(prompt ?? "", /## Additional context from \/review/);
	assert.match(prompt ?? "", /The user previously ran the \/review command/);
	assert.match(prompt ?? "", /# Review Results/);
	assert.match(prompt ?? "", /Finding one/);
	assert.doesNotMatch(prompt ?? "", /Queued review 1/);
});
