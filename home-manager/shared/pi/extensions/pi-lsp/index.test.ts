import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

type RegisteredTool = {
  execute: (
    toolCallId: string,
    params: Record<string, unknown>,
    signal: AbortSignal | undefined,
    onUpdate: (update: unknown) => void,
    ctx: Record<string, unknown>,
  ) => Promise<any>;
};

async function importWithConfigPath<T>(modulePath: string, configPath: string): Promise<T> {
  const previous = process.env.PI_LSP_CONFIG;
  process.env.PI_LSP_CONFIG = configPath;
  try {
    return (await import(`${modulePath}?test=${Date.now()}-${Math.random()}`)) as T;
  } finally {
    if (previous === undefined) delete process.env.PI_LSP_CONFIG;
    else process.env.PI_LSP_CONFIG = previous;
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
