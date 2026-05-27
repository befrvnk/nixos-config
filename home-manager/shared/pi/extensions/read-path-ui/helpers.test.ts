import assert from "node:assert/strict";
import test from "node:test";
import {
  backgroundColorForGroup,
  countLabel,
  firstNonEmptyLine,
  formatDisplayPath,
  formatLineRange,
  getResultText,
  readSummaryData,
  summaryHeader,
  summaryLine,
  type ThemeLike,
  type ToolSummaryData,
  type ToolSummaryStatus,
} from "./helpers.ts";

const theme: ThemeLike = {
  bold: (text) => text,
  fg: (_color, text) => text,
};

function makeData(status: ToolSummaryStatus, overrides: Partial<ToolSummaryData> = {}): ToolSummaryData {
  return {
    id: "id",
    kind: "read",
    title: "Read",
    countSingular: "file",
    countPlural: "files",
    item: "src/index.ts",
    status,
    loadingLabel: "Loading",
    failedLabel: "Failed to load",
    expanded: false,
    theme,
    ...overrides,
  };
}

test("formatDisplayPath relativizes inside cwd, strips @, keeps outside paths", () => {
  assert.equal(formatDisplayPath("src/index.ts", "/repo"), "src/index.ts");
  assert.equal(formatDisplayPath("@src/index.ts", "/repo"), "src/index.ts");
  assert.equal(formatDisplayPath("/repo/src/index.ts", "/repo"), "src/index.ts");
  assert.equal(formatDisplayPath("/other/file.ts", "/repo"), "/other/file.ts");
  assert.equal(formatDisplayPath(undefined, "/repo"), "unknown file");
  assert.equal(formatDisplayPath("@", "/repo"), "unknown file");
});

test("formatLineRange renders offset/limit combinations", () => {
  assert.equal(formatLineRange(undefined), "");
  assert.equal(formatLineRange({}), "");
  assert.equal(formatLineRange({ offset: 10 }), ":10");
  assert.equal(formatLineRange({ limit: 5 }), ":1-5");
  assert.equal(formatLineRange({ offset: 10, limit: 5 }), ":10-14");
  assert.equal(formatLineRange({ offset: 10, limit: 1 }), ":10-10");
  assert.equal(formatLineRange({ offset: "x", limit: NaN }), "");
});

test("getResultText joins text content and ignores non-text entries", () => {
  assert.equal(getResultText({ content: [{ type: "text", text: "a" }, { type: "text", text: "b" }] }), "a\nb");
  assert.equal(getResultText({ content: [{ type: "image" }, { type: "text", text: "only" }] }), "only");
  assert.equal(getResultText({ content: "nope" }), undefined);
  assert.equal(getResultText({}), undefined);
});

test("firstNonEmptyLine returns the first trimmed non-empty line", () => {
  assert.equal(firstNonEmptyLine("  \n  hello \nworld"), "hello");
  assert.equal(firstNonEmptyLine(""), undefined);
  assert.equal(firstNonEmptyLine(undefined), undefined);
});

test("countLabel pluralizes on count", () => {
  assert.equal(countLabel(1, makeData("success")), "1 file");
  assert.equal(countLabel(2, makeData("success")), "2 files");
});

test("summaryHeader renders title and count", () => {
  assert.equal(summaryHeader(2, makeData("success")), "Read 2 files");
});

test("summaryLine reflects status", () => {
  assert.match(summaryLine(makeData("loading")), /Loading/);
  assert.match(summaryLine(makeData("failed")), /Failed to load/);
  const success = summaryLine(makeData("success"));
  assert.doesNotMatch(success, /Loading|Failed/);
  assert.match(success, /src\/index\.ts/);
});

test("backgroundColorForGroup prioritizes failed over loading over success", () => {
  assert.equal(backgroundColorForGroup([makeData("success")]), "toolSuccessBg");
  assert.equal(backgroundColorForGroup([makeData("loading")]), "toolPendingBg");
  assert.equal(backgroundColorForGroup([makeData("failed")]), "toolErrorBg");
  assert.equal(backgroundColorForGroup([makeData("success"), makeData("loading")]), "toolPendingBg");
  assert.equal(backgroundColorForGroup([makeData("loading"), makeData("failed")]), "toolErrorBg");
});

test("readSummaryData composes item from path and line range", () => {
  const data = readSummaryData({
    id: "call-1",
    args: { file_path: "src/index.ts", offset: 10, limit: 5 },
    cwd: "/repo",
    status: "success",
    expanded: false,
    theme,
  });
  assert.equal(data.item, "src/index.ts:10-14");
  assert.equal(data.kind, "read");
  assert.equal(data.title, "Read");
  assert.equal(data.id, "call-1");
});
