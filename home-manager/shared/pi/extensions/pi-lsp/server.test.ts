import test from "node:test";
import assert from "node:assert/strict";
import {
  isLspNoProjectError,
  isMethodNotSupportedResponse,
  isNoProjectResponse,
  isUnsupportedLspMethodError,
  JsonRpcStreamParser,
  LspNoProjectError,
  UnsupportedLspMethodError,
} from "./server.ts";

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

test("isMethodNotSupportedResponse recognizes common LSP method-not-found payloads", () => {
  assert.equal(
    isMethodNotSupportedResponse("workspace/symbol", { code: -32601, message: "Method not found" }),
    true,
  );
  assert.equal(
    isMethodNotSupportedResponse("workspace/symbol", { message: "No such method workspace/symbol" }),
    true,
  );
  assert.equal(
    isMethodNotSupportedResponse("workspace/symbol", { message: "Internal error executing workspace/symbol" }),
    false,
  );
  assert.equal(
    isMethodNotSupportedResponse("workspace/symbol", { message: "Some other failure" }),
    false,
  );
});

test("UnsupportedLspMethodError carries method metadata", () => {
  const error = new UnsupportedLspMethodError("workspace/symbol", "nix", "/repo", "nil");

  assert.equal(isUnsupportedLspMethodError(error), true);
  assert.equal(isUnsupportedLspMethodError(error, "workspace/symbol"), true);
  assert.equal(isUnsupportedLspMethodError(error, "textDocument/hover"), false);
  assert.match(error.message, /nil does not support workspace\/symbol/);
});

test("isNoProjectResponse recognizes workspace symbol failures in non-project TypeScript roots", () => {
  assert.equal(
    isNoProjectResponse("workspace/symbol", { message: "TypeScript Server Error\nNo Project." }),
    true,
  );
  assert.equal(
    isNoProjectResponse("textDocument/hover", { message: "No Project." }),
    false,
  );
});

test("LspNoProjectError carries workspace metadata", () => {
  const error = new LspNoProjectError("workspace/symbol", "typescript", "/repo", "typescript-language-server");

  assert.equal(isLspNoProjectError(error), true);
  assert.equal(isLspNoProjectError(error, "workspace/symbol"), true);
  assert.equal(isLspNoProjectError(error, "textDocument/hover"), false);
  assert.match(error.message, /has no project for workspace\/symbol/);
});
