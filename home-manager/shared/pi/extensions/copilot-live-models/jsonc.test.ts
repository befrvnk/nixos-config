import assert from "node:assert/strict";
import test from "node:test";
import { parseJsonc, stripJsonComments } from "./jsonc.ts";

test("parseJsonc accepts comments and trailing commas", () => {
  assert.deepEqual(
    parseJsonc(`\ufeff{
      // line comment\r
      "providers": {
        "example": {
          "models": ["one", "two", /* final item */],
        },
      },
    }`),
    { providers: { example: { models: ["one", "two"] } } },
  );
});

test("stripJsonComments preserves strings, newlines, and token boundaries", () => {
  const input = `{
    "url": "https://example.test//not-comment",
    "literal": "/* not a comment */",
    "escaped": "\\\"//still-string",
    "value": 1/* comment */2
  }`;
  const stripped = stripJsonComments(input);

  assert.equal(stripped.length, input.length);
  assert.equal(stripped.split("\n").length, input.split("\n").length);
  assert.throws(() => JSON.parse(stripped), SyntaxError);
});

test("parseJsonc preserves punctuation and escapes inside strings", () => {
  assert.deepEqual(
    parseJsonc(String.raw`{"text":"comma, brace } bracket ] slash \\ quote \" and // /*"}`),
    { text: 'comma, brace } bracket ] slash \\ quote " and // /*' },
  );
});

test("parseJsonc accepts an EOF line comment and CRLF input", () => {
  assert.deepEqual(parseJsonc("{\r\n  \"ok\": true,\r\n}\r\n// eof"), { ok: true });
});

test("parseJsonc rejects unterminated block comments", () => {
  assert.throws(() => parseJsonc('{"ok": true /* nope'), /Unterminated block comment/);
});

test("parseJsonc remains strict JSON apart from comments and trailing commas", () => {
  for (const invalid of [
    "{ unquoted: true }",
    "{ 'single': true }",
    '{"value": NaN}',
    '{"value": Infinity}',
    '{"value": 0x10}',
    '{"values": [1,,]}',
    "1/* gap */2",
  ]) {
    assert.throws(() => parseJsonc(invalid), SyntaxError, invalid);
  }
});
