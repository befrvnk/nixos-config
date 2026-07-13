import assert from "node:assert/strict";
import test from "node:test";
import {
  mergeCopilotProviderConfig,
  parseModelsJson,
  stripJsonComments,
  writeCopilotModelsJson,
} from "./models-json.ts";
import type { CopilotLiveModel, CopilotModelsJsonWriterDeps, PiProviderConfig } from "./types.ts";

const providerConfig: PiProviderConfig = {
  name: "GitHub Copilot (live catalog)",
  baseUrl: "https://api.enterprise.githubcopilot.com",
  api: "openai-responses",
  apiKey: "$COPILOT_GITHUB_TOKEN",
  headers: { "X-GitHub-Api-Version": "2026-06-01" },
  models: [
    {
      id: "gpt-5.5",
      name: "GPT-5.5",
      api: "openai-responses",
      reasoning: true,
      input: ["text"],
      cost: { input: 10, output: 45, cacheRead: 1, cacheWrite: 0 },
      contextWindow: 1_050_000,
      maxTokens: 128_000,
    },
  ],
};

const liveModel: CopilotLiveModel = {
  id: "gpt-5.5",
  name: "GPT-5.5",
  vendor: "OpenAI",
  model_picker_enabled: true,
  supported_endpoints: ["/responses"],
  capabilities: {
    type: "chat",
    limits: { max_context_window_tokens: 1_050_000, max_prompt_tokens: 922_000, max_output_tokens: 128_000 },
    supports: { reasoning_effort: ["none", "low", "medium", "high", "xhigh"] },
  },
};

test("stripJsonComments preserves strings while removing line and block comments", () => {
  const stripped = stripJsonComments(`{
    // comment
    "url": "https://example.test//not-comment",
    /* block */
    "ok": true
  }`);

  assert.deepEqual(JSON.parse(stripped), { url: "https://example.test//not-comment", ok: true });
});

test("parseModelsJson accepts JSONC models.json", () => {
  assert.deepEqual(parseModelsJson(`{ // comment\n "providers": {}, }`), { providers: {} });
});

test("parseModelsJson rejects unsafe root and providers shapes", () => {
  for (const invalid of ["null", "[]", '{"providers": null}', '{"providers": []}']) {
    assert.throws(() => parseModelsJson(invalid), TypeError, invalid);
  }
});

test("mergeCopilotProviderConfig preserves unrelated providers", () => {
  const merged = mergeCopilotProviderConfig(
    {
      providers: {
        openrouter: { baseUrl: "https://openrouter.ai/api/v1" },
        "github-copilot": { models: [] },
      },
    },
    providerConfig,
  );

  assert.equal(merged.providers.openrouter?.baseUrl, "https://openrouter.ai/api/v1");
  assert.equal(merged.providers["github-copilot"]?.models?.[0]?.contextWindow, 1_050_000);
});

function createWriterDeps(options: { modelsJson?: string; modelsReadError?: Error } = {}): {
  deps: CopilotModelsJsonWriterDeps;
  writes: Record<string, string>;
  dirs: string[];
  debug: string[];
} {
  const writes: Record<string, string> = {};
  const dirs: string[] = [];
  const debug: string[] = [];
  return {
    writes,
    dirs,
    debug,
    deps: {
      now: () => 1_000,
      readTextFile: async (filePath) => {
        if (filePath.endsWith("auth.json")) {
          return JSON.stringify({
            "github-copilot": {
              type: "oauth",
              access: "tid=abc;proxy-ep=proxy.enterprise.githubcopilot.com;exp=999",
              expires: 100_000,
            },
          });
        }
        if (filePath.endsWith("models.json")) {
          if (options.modelsReadError) throw options.modelsReadError;
          if (options.modelsJson !== undefined) return options.modelsJson;
        }
        throw Object.assign(new Error(`missing ${filePath}`), { code: "ENOENT" });
      },
      fetchImpl: (async () =>
        new Response(JSON.stringify({ data: [liveModel] }), {
          status: 200,
          headers: { "content-type": "application/json" },
        })) as typeof fetch,
      ensureDir: async (dirPath) => {
        dirs.push(dirPath);
      },
      writeTextFileAtomic: async (filePath, text) => {
        writes[filePath] = text;
      },
      writeDebug: (message) => debug.push(message),
    },
  };
}

test("writeCopilotModelsJson fetches live models and preserves existing configuration", async () => {
  const { deps, dirs, writes } = createWriterDeps({
    modelsJson: `{
      // Preserve unrelated configuration while normalizing successful output.
      "customMetadata": { "enabled": true },
      "providers": { "openrouter": { "baseUrl": "https://openrouter.ai/api/v1" }, },
    }`,
  });

  assert.equal(await writeCopilotModelsJson(deps, { agentDir: "/tmp/pi-agent", contextReserveTokens: 128_000 }), true);
  assert.deepEqual(dirs, ["/tmp/pi-agent"]);

  const written = JSON.parse(writes["/tmp/pi-agent/models.json"]!);
  assert.deepEqual(written.customMetadata, { enabled: true });
  assert.equal(written.providers.openrouter.baseUrl, "https://openrouter.ai/api/v1");
  assert.equal(written.providers["github-copilot"].models[0].id, "gpt-5.5");
  assert.equal(written.providers["github-copilot"].models[0].contextWindow, 1_050_000);
});

test("writeCopilotModelsJson preserves corrupt existing models.json", async () => {
  const { deps, dirs, writes, debug } = createWriterDeps({ modelsJson: "not-json" });

  assert.equal(await writeCopilotModelsJson(deps, { agentDir: "/tmp/pi-agent", contextReserveTokens: 128_000 }), false);
  assert.deepEqual(dirs, []);
  assert.deepEqual(writes, {});
  assert.ok(debug.some((message) => message.includes("Preserving unreadable existing models.json")));
});

test("writeCopilotModelsJson preserves structurally invalid existing models.json", async () => {
  for (const modelsJson of ["null", "[]", '{"providers": null}', '{"providers": []}']) {
    const { deps, dirs, writes } = createWriterDeps({ modelsJson });
    assert.equal(
      await writeCopilotModelsJson(deps, { agentDir: "/tmp/pi-agent", contextReserveTokens: 128_000 }),
      false,
      modelsJson,
    );
    assert.deepEqual(dirs, []);
    assert.deepEqual(writes, {});
  }
});

test("writeCopilotModelsJson preserves models.json after non-ENOENT read errors", async () => {
  const readError = Object.assign(new Error("permission denied"), { code: "EACCES" });
  const { deps, dirs, writes } = createWriterDeps({ modelsReadError: readError });

  assert.equal(await writeCopilotModelsJson(deps, { agentDir: "/tmp/pi-agent", contextReserveTokens: 128_000 }), false);
  assert.deepEqual(dirs, []);
  assert.deepEqual(writes, {});
});
