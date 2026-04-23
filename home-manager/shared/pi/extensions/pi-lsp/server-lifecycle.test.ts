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
  id?: number | string;
  method?: string;
  params?: Record<string, unknown>;
  result?: unknown;
  error?: unknown;
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

function createMockChild(onMessage: (message: JsonRpcMessage, child: MockChild) => void): MockChild {
  const child = new EventEmitter() as MockChild;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.pid = 4242;
  child.kill = () => {
    queueMicrotask(() => child.emit("exit", 0, null));
    return true;
  };

  let pending = "";
  child.stdin.on("data", (chunk: Buffer | string) => {
    pending += chunk.toString();
    const decoded = decodeMessages(pending);
    pending = decoded.remainder;
    for (const message of decoded.messages) onMessage(message, child);
  });

  return child;
}

type MockChild = EventEmitter & {
  stdin: PassThrough;
  stdout: PassThrough;
  stderr: PassThrough;
  pid: number;
  kill: () => boolean;
};

async function waitFor(predicate: () => boolean, timeoutMs = 1_000, intervalMs = 10): Promise<void> {
  const deadline = Date.now() + timeoutMs;

  while (!predicate()) {
    if (Date.now() >= deadline) {
      throw new Error(`Timed out after ${timeoutMs}ms waiting for test condition.`);
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}

test("LspServer.start sends initialize with the workspace basename", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-root-"));
  let initializeMessage: JsonRpcMessage | undefined;

  const child = createMockChild((message, childProcess) => {
    if (message.method === "initialize") {
      initializeMessage = message;
    }

    if (typeof message.id === "number") {
      childProcess.stdout.write(
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

  const capabilities = initializeMessage?.params?.capabilities as
    | { window?: { workDoneProgress?: boolean } }
    | undefined;

  assert.equal(initializeMessage?.method, "initialize");
  assert.equal(workspaceFolders?.[0]?.name, path.basename(root));
  assert.equal(workspaceFolders?.[0]?.uri, pathToFileURL(root).href);
  assert.equal(capabilities?.window?.workDoneProgress, true);
});


test("LspServer distinguishes server requests from client responses during initialize", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-server-request-"));
  let acknowledgedProgressCreate = false;

  const child = createMockChild((message, childProcess) => {
    if (message.method === "initialize") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          method: "window/workDoneProgress/create",
          params: { token: "kotlin-import" },
        }),
      );
      return;
    }

    if (typeof message.id === "number" && message.method === undefined && message.result === null) {
      acknowledgedProgressCreate = true;
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: {},
        }),
      );
      return;
    }

    if (message.method === "shutdown") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: null,
        }),
      );
    }
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 200,
    },
    () => child as any,
  );

  await server.start();

  assert.equal(acknowledgedProgressCreate, true);
  assert.equal(server.getStatus().state, "indexing");
  assert.match(server.getRecentLogLines().join("\n"), /server-request.*window\/workDoneProgress\/create/);

  await server.stop();
});

test("LspServer acknowledges string-id server requests", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-string-server-request-"));
  let acknowledgedProgressCreate = false;

  const child = createMockChild((message, childProcess) => {
    if (message.method === "initialize") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: {},
        }),
      );
      return;
    }

    if (message.method === "initialized") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: "progress-create-1",
          method: "window/workDoneProgress/create",
          params: { token: "kotlin-import" },
        }),
      );
      return;
    }

    if (message.id === "progress-create-1" && message.method === undefined && message.result === null) {
      acknowledgedProgressCreate = true;
      return;
    }

    if (message.method === "shutdown") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: null,
        }),
      );
    }
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 200,
    },
    () => child as any,
  );

  await server.start();
  await waitFor(() => acknowledgedProgressCreate);

  assert.equal(acknowledgedProgressCreate, true);
  assert.match(server.getRecentLogLines().join("\n"), /server-request.*window\/workDoneProgress\/create/);

  await server.stop();
});

test("Kotlin LspServer enters indexing after initialize and retains recent stderr output", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-ready-"));
  const child = createMockChild((message, childProcess) => {
    if (message.method === "initialize") {
      childProcess.stderr.write("warming cache\nindexing workspace\n");
    }

    if (typeof message.id === "number") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: {},
        }),
      );
    }
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 200,
    },
    () => child as any,
  );

  await server.start();

  const status = server.getStatus();
  assert.equal(status.state, "indexing");
  assert.equal(status.restartCount, 0);
  assert.equal(status.pid, 4242);
  assert.ok(typeof status.startedAt === "number");
  assert.ok(typeof status.initializedAt === "number");
  assert.equal(status.readyAt, undefined);
  assert.deepEqual(status.lastStderrLines.slice(-2), ["warming cache", "indexing workspace"]);
  assert.match(server.getRecentLogLines().join("\n"), /stderr.*warming cache/);

  await server.stop();
});

test("Kotlin LspServer promotes indexing to ready when no progress notifications arrive", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-kotlin-no-progress-ready-"));
  const child = createMockChild((message, childProcess) => {
    if (typeof message.id === "number") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: {},
        }),
      );
    }
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 200,
      kotlinReadyWithoutProgressMs: 20,
    },
    () => child as any,
  );

  await server.start();
  await waitFor(() => server.getStatus().state === "ready");

  const status = server.getStatus();
  assert.equal(status.state, "ready");
  assert.ok(typeof status.readyAt === "number");
  assert.match(server.getRecentLogLines().join("\n"), /no Kotlin work-done progress observed/);

  await server.stop();
});

test("Kotlin LspServer promotes indexing to ready after work done progress completes", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-kotlin-progress-ready-"));

  const child = createMockChild((message, childProcess) => {
    if (message.method === "initialize") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: {},
        }),
      );
      return;
    }

    if (message.method === "initialized") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: 99,
          method: "window/workDoneProgress/create",
          params: { token: "kotlin-import" },
        }),
      );
      return;
    }

    if (message.id === 99 && message.method === undefined && message.result === null) {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          method: "$/progress",
          params: {
            token: "kotlin-import",
            value: { kind: "begin", title: "Indexing..." },
          },
        }),
      );
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          method: "$/progress",
          params: {
            token: "kotlin-import",
            value: { kind: "end", message: "Done" },
          },
        }),
      );
      return;
    }

    if (message.method === "shutdown") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: null,
        }),
      );
    }
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 200,
    },
    () => child as any,
  );

  await server.start();
  await waitFor(() => server.getStatus().state === "ready");

  const status = server.getStatus();
  assert.equal(status.state, "ready");
  assert.ok(typeof status.readyAt === "number");
  assert.match(server.getRecentLogLines().join("\n"), /progress.*Indexing\.\.\./);

  await server.stop();
});


test("Kotlin LspServer promotes indexing to ready when progress stalls", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-kotlin-stalled-progress-ready-"));

  const child = createMockChild((message, childProcess) => {
    if (message.method === "initialize") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: {},
        }),
      );
      return;
    }

    if (message.method === "initialized") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: 99,
          method: "window/workDoneProgress/create",
          params: { token: "kotlin-import" },
        }),
      );
      return;
    }

    if (message.id === 99 && message.method === undefined && message.result === null) {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          method: "$/progress",
          params: {
            token: "kotlin-import",
            value: { kind: "begin", title: "Indexing..." },
          },
        }),
      );
      return;
    }

    if (message.method === "shutdown") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: null,
        }),
      );
    }
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 200,
      kotlinStalledProgressTimeoutMs: 20,
    },
    () => child as any,
  );

  await server.start();
  await waitFor(() => server.getStatus().state === "ready");

  const status = server.getStatus();
  assert.equal(status.state, "ready");
  assert.ok(typeof status.readyAt === "number");
  assert.match(server.getRecentLogLines().join("\n"), /Kotlin progress stalled/);

  await server.stop();
});

test("Kotlin LspServer promotes indexing to ready after a successful semantic request", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-kotlin-promote-"));
  const child = createMockChild((message, childProcess) => {
    if (typeof message.id === "number") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: message.method === "textDocument/hover" ? { contents: "ready" } : {},
        }),
      );
    }
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 200,
    },
    () => child as any,
  );

  await server.start();
  await server.request("textDocument/hover", {
    textDocument: { uri: pathToFileURL(path.join(root, "App.kt")).href },
    position: { line: 0, character: 0 },
  });

  const status = server.getStatus();
  assert.equal(status.state, "ready");
  assert.ok(typeof status.readyAt === "number");

  await server.stop();
});

test("LspServer records initialize timeout failures in status", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-timeout-"));
  const child = createMockChild(() => {
    // Intentionally never respond to initialize.
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 20,
    },
    () => child as any,
  );

  await assert.rejects(server.start(), /Timed out waiting for initialize from kotlin/);

  const status = server.getStatus();
  assert.equal(status.state, "failed");
  assert.equal(status.lastFailure?.category, "initialize_timeout");
  assert.match(status.lastFailure?.message ?? "", /Timed out waiting for initialize from kotlin/);
});

test("Kotlin LspServer fails before spawn when another workspace session is already running", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-kotlin-workspace-conflict-"));
  let spawnCalled = false;

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 20,
    },
    () => {
      spawnCalled = true;
      return createMockChild(() => undefined) as any;
    },
    () => [5151],
  );

  await assert.rejects(server.start(), /Competing PID\(s\): 5151/);

  const status = server.getStatus();
  assert.equal(spawnCalled, false);
  assert.equal(status.state, "failed");
  assert.equal(status.lastFailure?.category, "workspace_session_conflict");
  assert.match(status.lastFailure?.message ?? "", /Competing PID\(s\): 5151/);
});

test("LspServer.restart increments restart count and re-initializes", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-restart-"));
  let initializeCalls = 0;

  const spawnProcess = () =>
    createMockChild((message, childProcess) => {
      if (message.method === "initialize") initializeCalls += 1;

      if (typeof message.id === "number") {
        childProcess.stdout.write(
          encodeMessage({
            jsonrpc: "2.0",
            id: message.id,
            result: {},
          }),
        );
      }
    }) as any;

  const server = new LspServer(
    "typescript",
    root,
    {
      command: "/bin/mock-typescript-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 200,
    },
    spawnProcess,
  );

  await server.start();
  await server.restart();

  const status = server.getStatus();
  assert.equal(status.state, "ready");
  assert.equal(status.restartCount, 1);
  assert.equal(initializeCalls, 2);

  await server.stop();
});

test("LspServer.waitUntilReady accepts indexing as requestable readiness when requested", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-indexing-ready-"));
  const child = createMockChild((message, childProcess) => {
    if (typeof message.id === "number") {
      childProcess.stdout.write(
        encodeMessage({
          jsonrpc: "2.0",
          id: message.id,
          result: {},
        }),
      );
    }
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 100,
    },
    () => child as any,
  );

  await server.start();
  await server.waitUntilReady({ maxWaitMs: 50, acceptIndexing: true });
  assert.equal(server.getStatus().state, "indexing");

  await server.stop();
});

test("LspServer.waitUntilReady honors abort signals while startup is still pending", async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-abort-"));
  const child = createMockChild(() => {
    // Intentionally never respond to initialize.
  });

  const server = new LspServer(
    "kotlin",
    root,
    {
      command: "/bin/mock-kotlin-language-server",
      args: ["--stdio"],
      startupTimeoutMs: 100,
    },
    () => child as any,
  );

  const startPromise = server.start().catch((error) => error);
  const controller = new AbortController();
  controller.abort();

  await assert.rejects(
    server.waitUntilReady({ signal: controller.signal, maxWaitMs: 200 }),
    /Aborted while waiting for LSP server readiness/,
  );

  await startPromise;
});
