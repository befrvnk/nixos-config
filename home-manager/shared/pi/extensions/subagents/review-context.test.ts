import test from "node:test";
import assert from "node:assert/strict";
import { buildReviewContextSystemPrompt } from "./review-context.ts";

test("buildReviewContextSystemPrompt returns undefined for empty input", () => {
	assert.equal(buildReviewContextSystemPrompt([]), undefined);
	assert.equal(buildReviewContextSystemPrompt(["", "   "]), undefined);
});

test("buildReviewContextSystemPrompt wraps a single review result", () => {
	const prompt = buildReviewContextSystemPrompt(["# Review Results\n- Finding one"]);

	assert.match(prompt ?? "", /## Additional context from \/review/);
	assert.match(prompt ?? "", /The user previously ran the \/review command/);
	assert.match(prompt ?? "", /# Review Results/);
	assert.doesNotMatch(prompt ?? "", /Queued review 1/);
});

test("buildReviewContextSystemPrompt labels multiple queued reviews", () => {
	const prompt = buildReviewContextSystemPrompt([
		"# Review Results\n- Finding one",
		"# Review Results\n- Finding two",
	]);

	assert.match(prompt ?? "", /### Queued review 1/);
	assert.match(prompt ?? "", /### Queued review 2/);
	assert.match(prompt ?? "", /Finding one/);
	assert.match(prompt ?? "", /Finding two/);
});
