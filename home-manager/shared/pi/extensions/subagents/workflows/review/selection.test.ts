import test from "node:test";
import assert from "node:assert/strict";
import {
	chooseSmartReviewTarget,
	rankReviewBranch,
	sortReviewBranches,
	summarizeGitStatusForReview,
} from "./selection.ts";

test("summarizeGitStatusForReview separates unstaged or untracked changes from staged ones", () => {
	assert.deepEqual(summarizeGitStatusForReview(""), {
		hasUncommittedChanges: false,
		hasStagedChanges: false,
	});
	assert.deepEqual(summarizeGitStatusForReview("M  src/index.ts"), {
		hasUncommittedChanges: false,
		hasStagedChanges: true,
	});
	assert.deepEqual(summarizeGitStatusForReview(" M src/index.ts\n?? notes.md"), {
		hasUncommittedChanges: true,
		hasStagedChanges: false,
	});
	assert.deepEqual(summarizeGitStatusForReview("MM src/index.ts"), {
		hasUncommittedChanges: true,
		hasStagedChanges: true,
	});
});

test("chooseSmartReviewTarget prefers uncommitted, then staged, then base-branch, then commit", () => {
	assert.equal(
		chooseSmartReviewTarget({
			statusShort: " M src/index.ts",
			currentBranch: "feature/foo",
			defaultBranch: "main",
		}),
		"uncommitted",
	);
	assert.equal(
		chooseSmartReviewTarget({
			statusShort: "M  src/index.ts",
			currentBranch: "feature/foo",
			defaultBranch: "main",
		}),
		"staged",
	);
	assert.equal(
		chooseSmartReviewTarget({
			statusShort: "",
			currentBranch: "feature/foo",
			defaultBranch: "main",
		}),
		"baseBranch",
	);
	assert.equal(
		chooseSmartReviewTarget({
			statusShort: "",
			currentBranch: "main",
			defaultBranch: "main",
		}),
		"commit",
	);
});

test("sortReviewBranches prioritizes common default branches and hides HEAD aliases", () => {
	assert.deepEqual(
		sortReviewBranches(
			["feature/z", "origin/main", "main", "origin/HEAD", "feature/a"],
			"feature/a",
		),
		["main", "origin/main", "feature/z"],
	);
	assert.ok(rankReviewBranch("main") < rankReviewBranch("feature/test"));
});
