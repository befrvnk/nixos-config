import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { LspServer } from "./server.ts";

type JsonRpcMessage = {
  id?: number;
  method?: string;
  params?: Record<string, unknown>;
};

function encodeMessage(payload: unknown): string {
  const body = JSON.stringify(payload);
  return `Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`;
}

function decodeMessages(buffer: string): { messages: JsonRpcMessage[]; remainder: string } {
  const messages: JsonRpcMessage[] = [];
  let remaining = buffer;

  while (true) {
    const headerEnd = remaining.indexOf("\r\n\r\n");
    if (headerEnd === -1) break;

    const header = remaining.slice(0, headerEnd);
    const match = header.match(/Content-Length:\s*(\d+)/i);
    if (!match) {
      remaining = remaining.slice(headerEnd + 4);
      continue;
    }

    const contentLength = Number(match[1]);
    const bodyStart = headerEnd + 4;
    const bodyEnd = bodyStart + contentLength;
    if (remaining.length < bodyEnd) break;

    messages.push(JSON.parse(remaining.slice(bodyStart, bodyEnd)) as JsonRpcMessage);
    remaining = remaining.slice(bodyEnd);
  }

  return { messages, remainder: remaining };
}

function createMockChild(onMessage: (message: JsonRpcMessage) => void) {
  const child = new EventEmitter() as EventEmitter & {
    stdin: PassThrough;
    stdout: PassThrough;
    stderr: PassThrough;
    pid: number;
    kill: () => boolean;
  };
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.pid = 4242;
  child.kill = () => true;

  let pending = "";
  child.stdin.on("data", (chunk: Buffer | string) => {
    pending += chunk.toString();
    const decoded = decodeMessages(pending);
    pending = decoded.remainder;
    for (const message of decoded.messages) onMessage(message);
  });

  return child;
}

test("LspServer.start sends initialize with the workspace basename", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-root-"));
  let initializeMessage: JsonRpcMessage | undefined;

  const child = createMockChild((message) => {
    if (message.method === "initialize") {
      initializeMessage = message;
    }

    if (typeof message.id === "number") {
      child.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: {},
        }),
      );
    }
  });

  const server = new LspServer(
    "typescript",
    root,
    {
      command: "/bin/mock-typescript-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 200,
    },
    () => child as any,
  );

  await server.start();
  await server.stop();

  const workspaceFolders = initializeMessage?.params?.workspaceFolders as
    | Array<{ name?: string; uri?: string }>
    | undefined;

  assert.equal(initializeMessage?.method, "initialize");
  assert.equal(workspaceFolders?.[0]?.name, path.basename(root));
  assert.equal(workspaceFolders?.[0]?.uri, pathToFileURL(root).href);
});
