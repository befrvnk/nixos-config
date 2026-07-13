import assert from "node:assert/strict";
import test from "node:test";
import { calculateAnswerLayout } from "./layout.ts";

test("calculateAnswerLayout remains within narrow and wide render widths", () => {
  for (const width of [0, 1, 2, 10, 29, 30, 34, 80, 200]) {
    const layout = calculateAnswerLayout(width);
    assert.ok(layout.renderWidth >= 0);
    assert.ok(layout.boxWidth >= 0);
    assert.ok(layout.contentWidth >= 0);
    assert.ok(layout.editorWidth >= 1);
    assert.ok(layout.boxWidth <= layout.renderWidth);
    assert.ok(layout.contentWidth <= layout.boxWidth);
  }
});

test("calculateAnswerLayout caps normal dialogs while preserving narrow safety", () => {
  assert.deepEqual(calculateAnswerLayout(0), {
    renderWidth: 0,
    boxWidth: 0,
    contentWidth: 0,
    editorWidth: 1,
    compact: true,
  });
  assert.equal(calculateAnswerLayout(200).boxWidth, 120);
  assert.equal(calculateAnswerLayout(34).boxWidth, 30);
});
