import test from "node:test";
import assert from "node:assert/strict";
import {
  classifyLspFailure,
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

test("classifyLspFailure distinguishes initialize timeouts and unsupported methods", () => {
  const timeoutFailure = classifyLspFailure(new Error("Timed out waiting for initialize from kotlin"), {
    method: "initialize",
  });
  assert.equal(timeoutFailure.category, "initialize_timeout");
  assert.equal(timeoutFailure.method, "initialize");

  const unsupportedFailure = classifyLspFailure(
    new UnsupportedLspMethodError("workspace/symbol", "nix", "/repo", "nil"),
  );
  assert.equal(unsupportedFailure.category, "unsupported_method");
  assert.equal(unsupportedFailure.method, "workspace/symbol");

  const noProjectFailure = classifyLspFailure(
    new LspNoProjectError("workspace/symbol", "typescript", "/repo", "typescript-language-server"),
  );
  assert.equal(noProjectFailure.category, "no_project");
  assert.equal(noProjectFailure.method, "workspace/symbol");
});

test("classifyLspFailure explains likely Kotlin workspace session conflicts", () => {
  const likelyConflict = classifyLspFailure(new Error("cancelled"), {
    method: "initialize",
    language: "kotlin",
    root: "/repo",
  });
  assert.equal(likelyConflict.category, "initialize_failed");
  assert.match(likelyConflict.message, /Multiple editing sessions for one workspace are not supported yet/);

  const explicitConflict = classifyLspFailure(
    new Error("Multiple editing sessions for one workspace are not supported yet"),
    {
      method: "initialize",
      language: "kotlin",
      root: "/repo",
    },
  );
  assert.equal(explicitConflict.category, "workspace_session_conflict");
  assert.match(explicitConflict.message, /Stop the other Kotlin LSP session for this workspace/i);
});
