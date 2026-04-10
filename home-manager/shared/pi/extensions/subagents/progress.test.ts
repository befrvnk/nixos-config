import test from "node:test";
import assert from "node:assert/strict";
import {
  cleanParsedOutput,
  extractLatestProgress,
  parseProgressItems,
  stripProgressBlocks,
} from "./progress.ts";

test("parseProgressItems extracts checkbox state and text", () => {
  assert.deepEqual(
    parseProgressItems("- [x] Read docs\n- [ ] Update tests\nignored"),
    [
      { done: true, text: "Read docs" },
      { done: false, text: "Update tests" },
    ],
  );
});

test("extractLatestProgress returns the most recent progress block", () => {
  const text = [
    "intro",
    "[[progress]]\n- [x] First\n- [ ] Second\n[[/progress]]",
    "middle",
    "[[progress]]\n- [x] New first\n- [ ] New second\n[[/progress]]",
  ].join("\n\n");

  assert.deepEqual(extractLatestProgress(text), [
    { done: true, text: "New first" },
    { done: false, text: "New second" },
  ]);
  assert.equal(extractLatestProgress("no blocks here"), undefined);
});

test("stripProgressBlocks and cleanParsedOutput remove progress markup from summaries", () => {
  const summary = [
    "Before",
    "[[progress]]\n- [x] done\n- [ ] next\n[[/progress]]",
    "After",
  ].join("\n");

  assert.equal(stripProgressBlocks(summary), "Before\nAfter");
  assert.deepEqual(cleanParsedOutput({ summary, data: { keep: true } }), {
    summary: "Before\nAfter",
    data: { keep: true },
  });
});
