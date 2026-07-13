import assert from "node:assert/strict";
import test from "node:test";
import { buildBashOutputView } from "./filtering.ts";
import { buildBashToolDetails } from "./details.ts";

test("buildBashToolDetails reports complete output with the built-in shape", () => {
  const details = buildBashToolDetails(buildBashOutputView("one\ntwo\n", {}));
  assert.deepEqual(details, {
    truncation: {
      content: "one\ntwo",
      truncated: false,
      truncatedBy: null,
      totalLines: 2,
      totalBytes: 8,
      outputLines: 2,
      outputBytes: 7,
    },
    fullOutputPath: undefined,
  });
});

test("buildBashToolDetails reports line and filter omissions", () => {
  const tailed = buildBashToolDetails(buildBashOutputView("one\ntwo\nthree\n", { tailLines: 1 }), "/tmp/full");
  assert.equal(tailed.truncation?.truncated, true);
  assert.equal(tailed.truncation?.truncatedBy, "lines");
  assert.equal(tailed.fullOutputPath, "/tmp/full");

  const filtered = buildBashToolDetails(buildBashOutputView("keep\ndrop\n", { include: ["keep"] }));
  assert.equal(filtered.truncation?.truncated, true);
  assert.equal(filtered.truncation?.truncatedBy, "lines");
});

test("buildBashToolDetails gives byte truncation precedence", () => {
  const details = buildBashToolDetails(buildBashOutputView("one\ntwo\nthree\n", { tailLines: 1, maxBytes: 2 }));
  assert.equal(details.truncation?.truncated, true);
  assert.equal(details.truncation?.truncatedBy, "bytes");
  assert.equal(details.truncation?.outputBytes, 2);
});
