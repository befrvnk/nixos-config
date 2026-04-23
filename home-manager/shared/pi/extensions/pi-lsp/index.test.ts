import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { ServerManager } from "./server.ts";

type RegisteredTool = {
  execute: (
    toolCallId: string,
    params: Record<string, unknown>,
    signal: AbortSignal | undefined,
    onUpdate: (update: unknown) => void,
    ctx: Record<string, unknown>,
  ) => Promise<any>;
};

let configImportQueue = Promise.resolve();

async function importWithConfigPath<T>(modulePath: string, configPath: string): Promise<T> {
  const previousQueue = configImportQueue;
  let releaseQueue: (() => void) | undefined;
  configImportQueue = new Promise<void>((resolve) => {
    releaseQueue = resolve;
  });

  await previousQueue;

  const previous = process.env.PI_LSP_CONFIG;
  process.env.PI_LSP_CONFIG = configPath;
  try {
    return (await import(`${modulePath}?test=${Date.now()}-${Math.random()}`)) as T;
  } finally {
    if (previous === undefined) delete process.env.PI_LSP_CONFIG;
    else process.env.PI_LSP_CONFIG = previous;
    releaseQueue?.();
  }
}

function createMockPi() {
  const tools = new Map<string, RegisteredTool>();
  const events = new Map<string, Function>();

  return {
    tools,
    events,
    registerTool(tool: { name: string } & RegisteredTool) {
      tools.set(tool.name, tool);
    },
    registerCommand() {
      // Not needed for these tests.
    },
    on(event: string, handler: Function) {
      events.set(event, handler);
    },
  };
}

function writeMockLspServerScript(scriptPath: string) {
  fs.writeFileSync(
    scriptPath,
    [
      'let buffer = "";',
      "",
      "function writeMessage(message) {",
      "  const body = JSON.stringify(message);",
      '  process.stdout.write(`Content-Length: ${Buffer.byteLength(body, "utf8")}\\r\\n\\r\\n${body}`);',
      "}",
      "",
      "function flush() {",
      "  while (true) {",
      '    const headerEnd = buffer.indexOf("\\r\\n\\r\\n");',
      "    if (headerEnd === -1) return;",
      "",
      "    const header = buffer.slice(0, headerEnd);",
      '    const match = header.match(/Content-Length:\\s*(\\d+)/i);',
      "    if (!match) {",
      "      buffer = buffer.slice(headerEnd + 4);",
      "      continue;",
      "    }",
      "",
      "    const contentLength = Number(match[1]);",
      "    const bodyStart = headerEnd + 4;",
      "    const bodyEnd = bodyStart + contentLength;",
      "    if (buffer.length < bodyEnd) return;",
      "",
      "    const message = JSON.parse(buffer.slice(bodyStart, bodyEnd));",
      "    buffer = buffer.slice(bodyEnd);",
      "",
      '    if (typeof message.id === "number") {',
      "      writeMessage({",
      '        jsonrpc: "2.0",',
      "        id: message.id,",
      '        result: message.method === "shutdown" ? null : {},',
      "      });",
      "      continue;",
      "    }",
      "",
      '    if (message.method === "exit") {',
      "      process.exit(0);",
      "    }",
      "  }",
      "}",
      "",
      'process.stdin.setEncoding("utf8");',
      'process.stdin.resume();',
      'process.stdin.on("data", (chunk) => {',
      "  buffer += chunk;",
      "  flush();",
      "});",
      "",
    ].join("\n"),
  );
}

async function waitFor(predicate: () => boolean, timeoutMs = 1_000, intervalMs = 10): Promise<void> {
  const deadline = Date.now() + timeoutMs;

  while (!predicate()) {
    if (Date.now() >= deadline) {
      throw new Error(`Timed out after ${timeoutMs}ms waiting for test condition.`);
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}

test("workspace_symbols skips Kotlin non-project roots and warmup detection ignores bare git repos", async () => {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-index-workspace-"));
  const configPath = path.join(workspace, "pi-lsp.json");

  fs.mkdirSync(path.join(workspace, ".git"));
  fs.writeFileSync(
    configPath,
    JSON.stringify({
      servers: {
        kotlin: {
          command: process.execPath,
          args: ["-e", "process.exit(1)"],
          startupTimeoutMs: 100,
        },
        typescript: {
          command: process.execPath,
          args: ["-e", "process.exit(1)"],
          startupTimeoutMs: 100,
        },
        nix: {
          command: process.execPath,
          args: ["-e", "process.exit(1)"],
          startupTimeoutMs: 100,
        },
      },
    }),
  );

  const { default: piLspExtension, detectLikelyWorkspaceLanguages } =
    await importWithConfigPath<typeof import("./index.ts")>("./index.ts", configPath);
  assert.deepEqual(detectLikelyWorkspaceLanguages(workspace), []);
  const pi = createMockPi();
  piLspExtension(pi as any);

  const tool = pi.tools.get("workspace_symbols");
  assert.ok(tool, "workspace_symbols tool should be registered");

  const result = await tool!.execute(
    "call-1",
    { query: "App" },
    undefined,
    () => undefined,
    {
      cwd: workspace,
      hasUI: false,
    },
  );

  assert.equal(result.details.action, "workspace_symbols");
  assert.equal(result.details.noProject.length, 1);
  assert.equal(result.details.noProject[0].language, "kotlin");
  assert.match(
    result.content[0].text,
    /kotlin \(project detection\) could not answer workspace_symbols because this workspace is not a recognized project/i,
  );
  assert.match(result.content[0].text, /Unavailable: .*typescript:/);
  assert.match(result.content[0].text, /Unavailable: .*nix:/);

  fs.writeFileSync(path.join(workspace, "devenv.nix"), "{ pkgs, ... }: { }\n");
  assert.deepEqual(detectLikelyWorkspaceLanguages(workspace), ["nix"]);

  fs.writeFileSync(path.join(workspace, "package.json"), "{}\n");
  assert.deepEqual(detectLikelyWorkspaceLanguages(workspace), ["typescript", "nix"]);
});

test("ServerManager notifies listeners when Kotlin warmup becomes ready asynchronously", async () => {
  const workspace = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-status-workspace-"));
  const serverScriptPath = path.join(workspace, "mock-kotlin-lsp.js");
  writeMockLspServerScript(serverScriptPath);

  const manager = new ServerManager({
    servers: {
      kotlin: {
        command: process.execPath,
        args: [serverScriptPath],
        startupTimeoutMs: 200,
        kotlinReadyWithoutProgressMs: 20,
      },
    },
  });

  const states: string[] = [];
  const unsubscribe = manager.onStatusChange(() => {
    states.push(manager.getStatus()[0]?.state ?? "idle");
  });

  const server = manager.warm("kotlin", workspace);
  await server.waitUntilReady({ maxWaitMs: 1_000, acceptIndexing: true });
  await waitFor(() => manager.getStatus()[0]?.state === "ready");

  assert.ok(states.includes("indexing"), `expected indexing update, saw: ${states.join(" | ")}`);
  assert.equal(manager.getStatus()[0]?.state, "ready");
  assert.equal(states.at(-1), "ready");

  unsubscribe();
  await manager.shutdown();
});
