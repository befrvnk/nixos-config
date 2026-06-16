import assert from "node:assert/strict";
import test from "node:test";
import {
  BashOutputViewAccumulator,
  buildBashOutputView,
  formatByteSize,
  normalizeBashOutputViewOptions,
  summarizeFilters,
} from "./filtering.ts";

test("buildBashOutputView keeps the last tailLines", () => {
  const view = buildBashOutputView("one\ntwo\nthree\nfour\n", { tailLines: 2 });

  assert.equal(view.text, "three\nfour");
  assert.equal(view.stats.totalLines, 4);
  assert.equal(view.stats.matchedLines, 4);
  assert.equal(view.stats.displayedLines, 2);
  assert.equal(view.stats.omittedMatchingLines, 2);
});

test("buildBashOutputView applies include and exclude filters", () => {
  const view = buildBashOutputView("INFO boot\nWARN noisy\nERROR failed\nINFO done", {
    include: ["warn|error"],
    exclude: ["noisy"],
    ignoreCase: true,
  });

  assert.equal(view.text, "ERROR failed");
  assert.equal(view.stats.totalLines, 4);
  assert.equal(view.stats.matchedLines, 1);
  assert.equal(view.stats.hasFilters, true);
});

test("literal filter mode escapes regex metacharacters", () => {
  const view = buildBashOutputView("task [a]\ntask ab", {
    include: ["[a]"],
    filterMode: "literal",
  });

  assert.equal(view.text, "task [a]");
});

test("maxBytes keeps the end of the tailed output", () => {
  const view = buildBashOutputView("alpha\nbeta\ngamma", { maxBytes: 9 });

  assert.equal(view.text, "eta\ngamma");
  assert.equal(view.stats.truncatedByBytes, true);
});

test("maxBytes drops partial leading UTF-8 codepoints cleanly", () => {
  const view = buildBashOutputView("🙂abc", { maxBytes: 5 });

  assert.equal(view.text, "abc");
  assert.doesNotMatch(view.text, /\uFFFD/);
});

test("tailLines zero hides display while preserving stats", () => {
  const view = buildBashOutputView("one\ntwo", { tailLines: 0 });

  assert.equal(view.text, "");
  assert.equal(view.stats.totalLines, 2);
  assert.equal(view.stats.matchedLines, 2);
  assert.equal(view.stats.displayedLines, 0);
});

test("BashOutputViewAccumulator rejects invalid regex filters before data is appended", () => {
  assert.throws(() => new BashOutputViewAccumulator({ include: ["["] }), SyntaxError);
});

test("BashOutputViewAccumulator matches whole-output helper across chunks", () => {
  const accumulator = new BashOutputViewAccumulator({ include: ["error"], ignoreCase: true, tailLines: 1 });
  accumulator.append("info boot\nERR");
  accumulator.append("OR first\nwarn\nerror second\n");

  const streamed = accumulator.finish();
  const whole = buildBashOutputView("info boot\nERROR first\nwarn\nerror second\n", {
    include: ["error"],
    ignoreCase: true,
    tailLines: 1,
  });

  assert.deepEqual(streamed, whole);
});

test("BashOutputViewAccumulator matches whole-output helper for line ending edge cases", () => {
  for (const output of ["", "no trailing newline", "one\r\ntwo\rthree\n", "one\r"]) {
    const accumulator = new BashOutputViewAccumulator({ tailLines: 10 });
    accumulator.append(output.slice(0, 3));
    accumulator.append(output.slice(3));

    assert.deepEqual(accumulator.finish(), buildBashOutputView(output, { tailLines: 10 }));
  }
});

test("BashOutputViewAccumulator handles CRLF split across chunks", () => {
  const accumulator = new BashOutputViewAccumulator({ tailLines: 10 });
  accumulator.append("one\r");
  accumulator.append("\ntwo");

  assert.deepEqual(accumulator.finish(), buildBashOutputView("one\r\ntwo", { tailLines: 10 }));
});

test("options are clamped to safe bounds", () => {
  const options = normalizeBashOutputViewOptions({ tailLines: 999_999, maxBytes: 999_999_999 });

  assert.equal(options.tailLines, 20_000);
  assert.equal(options.maxBytes, 1024 * 1024);
});

test("filter summaries and byte sizes are compact", () => {
  assert.equal(
    summarizeFilters({ include: ["ERROR"], exclude: ["deprecated"], filterMode: "literal", ignoreCase: true }),
    'include="ERROR"; exclude="deprecated"; mode=literal; ignoreCase=true',
  );
  assert.equal(formatByteSize(512), "512B");
  assert.equal(formatByteSize(1536), "1.5KB");
});
