import test from "node:test";
import assert from "node:assert/strict";
import { JsonRpcStreamParser } from "./server.ts";

function encodeMessage(payload: unknown): Buffer {
  const body = JSON.stringify(payload);
  return Buffer.from(`Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`);
}

test("JsonRpcStreamParser buffers partial frames until complete", () => {
  const parser = new JsonRpcStreamParser();
  const message = encodeMessage({ jsonrpc: "2.0", id: 1, result: { ok: true } });

  const first = parser.push(message.subarray(0, 12));
  const second = parser.push(message.subarray(12));

  assert.deepEqual(first, []);
  assert.deepEqual(second, [{ jsonrpc: "2.0", id: 1, result: { ok: true } }]);
});

test("JsonRpcStreamParser can parse multiple messages from one chunk", () => {
  const parser = new JsonRpcStreamParser();
  const chunk = Buffer.concat([
    encodeMessage({ jsonrpc: "2.0", id: 1, result: "one" }),
    encodeMessage({ jsonrpc: "2.0", id: 2, result: "two" }),
  ]);

  assert.deepEqual(parser.push(chunk), [
    { jsonrpc: "2.0", id: 1, result: "one" },
    { jsonrpc: "2.0", id: 2, result: "two" },
  ]);
});

test("JsonRpcStreamParser ignores malformed payloads and missing content-length headers", () => {
  const parser = new JsonRpcStreamParser();
  const missingLength = Buffer.from("Header: nope\r\n\r\n{}");
  const malformedJson = Buffer.from("Content-Length: 5\r\n\r\nnope!");

  assert.deepEqual(parser.push(missingLength), []);
  assert.deepEqual(parser.push(malformedJson), []);
});
