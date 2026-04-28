import assert from "node:assert/strict";
import test from "node:test";
import {
  normalizeLanguage,
  renderCodeBlockLines,
} from "./render-code-block.ts";

const identity = (text: string) => text;
const utilities = {
  truncateToWidth: (text: string, width: number, ellipsis = "") =>
    text.length > width ? `${text.slice(0, Math.max(0, width - ellipsis.length))}${ellipsis}` : text,
  visibleWidth: (text: string) => text.length,
  wrapTextWithAnsi: (text: string, width: number) => {
    const lines: string[] = [];
    for (let i = 0; i < text.length; i += width) lines.push(text.slice(i, i + width));
    return lines.length > 0 ? lines : [""];
  },
};
const theme = {
  codeBlock: identity,
  codeBlockBorder: identity,
  highlightCode: (code: string, lang?: string) =>
    code.split("\n").map((line) => (lang ? `[${lang}] ${line}` : line)),
};

test("normalizeLanguage maps common fence aliases", () => {
  assert.equal(normalizeLanguage("kt"), "kotlin");
  assert.equal(normalizeLanguage("kts"), "kotlin");
  assert.equal(normalizeLanguage("ts"), "typescript");
  assert.equal(normalizeLanguage("shell"), "bash");
  assert.equal(normalizeLanguage("text"), undefined);
  assert.equal(normalizeLanguage("kotlin title=Main.kt"), "kotlin");
});

test("renderCodeBlockLines renders fenced code as bounded highlighted blocks", () => {
  const lines = renderCodeBlockLines(
    theme,
    {
      lang: "kt",
      text: 'fun main() {\n  println("hi")\n}',
    },
    48,
    undefined,
    utilities,
  );

  assert.deepEqual(lines, [
    "╭─ kt ─────────────────────────────────────────╮",
    "│ [kotlin] fun main() {",
    '│ [kotlin]   println("hi")',
    "│ [kotlin] }",
    "╰──────────────────────────────────────────────╯",
  ]);
});

test("renderCodeBlockLines wraps long code lines to the render width", () => {
  const lines = renderCodeBlockLines(
    theme,
    { lang: "text", text: "x".repeat(80) },
    30,
    undefined,
    utilities,
  );

  assert(lines.every((line) => line.length <= 30));
  assert.deepEqual(lines, [
    "╭─ text ─────────────────────╮",
    "│ xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "│ xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "│ xxxxxxxxxxxxxxxxxxxxxxxx",
    "╰────────────────────────────╯",
  ]);
});
