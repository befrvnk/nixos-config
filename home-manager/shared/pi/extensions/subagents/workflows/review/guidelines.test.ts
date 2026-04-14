import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import {
	composeAdditionalReviewInstructions,
	findProjectReviewGuidelinesPath,
	loadProjectReviewGuidelines,
} from "./guidelines.ts";

async function makeTempDir(): Promise<string> {
	return fs.mkdtemp(path.join(os.tmpdir(), "subagents-review-guidelines-"));
}

test("findProjectReviewGuidelinesPath returns the repo-level REVIEW_GUIDELINES.md next to .pi", async () => {
	const root = await makeTempDir();
	const nested = path.join(root, "packages", "app", "src");
	const guidelinesPath = path.join(root, "REVIEW_GUIDELINES.md");
	await fs.mkdir(path.join(root, ".pi"), { recursive: true });
	await fs.mkdir(nested, { recursive: true });
	await fs.writeFile(guidelinesPath, "Follow the checklist.\n");

	const found = await findProjectReviewGuidelinesPath(nested);
	assert.equal(found, guidelinesPath);

	await fs.rm(root, { recursive: true, force: true });
});

test("loadProjectReviewGuidelines ignores missing or blank files", async () => {
	const root = await makeTempDir();
	const nested = path.join(root, "src");
	await fs.mkdir(path.join(root, ".pi"), { recursive: true });
	await fs.mkdir(nested, { recursive: true });

	assert.equal(await loadProjectReviewGuidelines(nested), undefined);

	await fs.writeFile(path.join(root, "REVIEW_GUIDELINES.md"), "   \n\n");
	assert.equal(await loadProjectReviewGuidelines(nested), undefined);

	await fs.rm(root, { recursive: true, force: true });
});

test("composeAdditionalReviewInstructions combines user focus and project guidelines", () => {
	assert.equal(
		composeAdditionalReviewInstructions({}),
		undefined,
	);

	assert.equal(
		composeAdditionalReviewInstructions({ extraPrompt: "Check rollback safety." }),
		"User-provided focus:\nCheck rollback safety.",
	);

	assert.equal(
		composeAdditionalReviewInstructions({ projectGuidelines: "Prefer tests." }),
		"Project review guidelines (from REVIEW_GUIDELINES.md):\nPrefer tests.",
	);

	assert.equal(
		composeAdditionalReviewInstructions({
			extraPrompt: "Check rollback safety.",
			projectGuidelines: "Prefer tests.",
		}),
		[
			"User-provided focus:",
			"Check rollback safety.",
			"",
			"Project review guidelines (from REVIEW_GUIDELINES.md):",
			"Prefer tests.",
		].join("\n"),
	);
});
