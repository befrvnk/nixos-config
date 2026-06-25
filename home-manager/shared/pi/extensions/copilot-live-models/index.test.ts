import assert from "node:assert/strict";
import test from "node:test";
import {
  discoverCopilotProviderConfig,
  fetchWithTimeout,
  parseFetchTimeoutMs,
  registerCopilotLiveModels,
} from "./index.ts";
import type { CopilotLiveModel, CopilotLiveModelsProviderDeps } from "./types.ts";

const ACCESS_TOKEN = "tid=abc;proxy-ep=proxy.enterprise.githubcopilot.com;exp=999";

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

function createDeps(): { deps: CopilotLiveModelsProviderDeps; urls: string[] } {
  const urls: string[] = [];
  return {
    urls,
    deps: {
      now: () => 1_000,
      readTextFile: async (filePath) => {
        if (filePath.endsWith("auth.json")) {
          return JSON.stringify({
            "github-copilot": {
              type: "oauth",
              access: ACCESS_TOKEN,
              expires: 100_000,
            },
          });
        }
        if (filePath.endsWith("settings.json")) {
          return JSON.stringify({ compaction: { reserveTokens: 128_000 } });
        }
        throw new Error(`unexpected file: ${filePath}`);
      },
      fetchImpl: (async (url) => {
        urls.push(String(url));
        return new Response(JSON.stringify({ data: [liveModel] }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }) as typeof fetch,
      writeDebug: () => undefined,
    },
  };
}

test("discoverCopilotProviderConfig builds a provider from cached auth and live models", async () => {
  const { deps, urls } = createDeps();

  const provider = await discoverCopilotProviderConfig(deps, {
    agentDir: "/tmp/pi-agent",
    contextReserveTokens: 128_000,
  });

  assert.equal(urls.length, 1);
  assert.equal(urls[0], "https://api.enterprise.githubcopilot.com/models");
  assert.equal(provider?.baseUrl, "https://api.enterprise.githubcopilot.com");
  assert.equal(provider?.models?.[0]?.contextWindow, 1_050_000);
});

test("registerCopilotLiveModels registers github-copilot when discovery succeeds", async () => {
  const previousSkip = process.env.PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION;
  const previousEnabled = process.env.PI_COPILOT_LIVE_MODELS;
  delete process.env.PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION;
  delete process.env.PI_COPILOT_LIVE_MODELS;

  try {
    const { deps } = createDeps();
    const calls: Array<{ provider: string; config: any }> = [];

    const registered = await registerCopilotLiveModels(
      {
        registerProvider(provider: string, config: any) {
          calls.push({ provider, config });
        },
      } as any,
      deps,
      { agentDir: "/tmp/pi-agent" },
    );

    assert.equal(registered, true);
    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.provider, "github-copilot");
    assert.equal(calls[0]?.config.models[0].id, "gpt-5.5");
  } finally {
    if (previousSkip === undefined) {
      delete process.env.PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION;
    } else {
      process.env.PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION = previousSkip;
    }

    if (previousEnabled === undefined) {
      delete process.env.PI_COPILOT_LIVE_MODELS;
    } else {
      process.env.PI_COPILOT_LIVE_MODELS = previousEnabled;
    }
  }
});

test("fetchWithTimeout supplies an AbortSignal when the caller does not", async () => {
  let observedSignal: AbortSignal | undefined;
  const wrapped = fetchWithTimeout(
    (async (_url, init) => {
      observedSignal = init?.signal ?? undefined;
      return new Response("{}");
    }) as typeof fetch,
    5_000,
  );

  await wrapped("https://example.test");
  assert.ok(observedSignal instanceof AbortSignal);
});

test("parseFetchTimeoutMs falls back for invalid values", () => {
  assert.equal(parseFetchTimeoutMs(undefined), 10_000);
  assert.equal(parseFetchTimeoutMs("0"), 10_000);
  assert.equal(parseFetchTimeoutMs("2500"), 2_500);
});

test("registerCopilotLiveModels can skip duplicate session registration after wrapper refresh", async () => {
  const previous = process.env.PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION;
  process.env.PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION = "1";
  try {
    const calls: unknown[] = [];
    const registered = await registerCopilotLiveModels(
      { registerProvider: () => calls.push(true) } as any,
      createDeps().deps,
      { agentDir: "/tmp/pi-agent", contextReserveTokens: 128_000 },
    );

    assert.equal(registered, false);
    assert.equal(calls.length, 0);
  } finally {
    if (previous === undefined) {
      delete process.env.PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION;
    } else {
      process.env.PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION = previous;
    }
  }
});

test("registerCopilotLiveModels keeps built-ins when auth is unavailable", async () => {
  const calls: unknown[] = [];
  const registered = await registerCopilotLiveModels(
    { registerProvider: () => calls.push(true) } as any,
    {
      now: () => 1_000,
      readTextFile: async () => {
        throw new Error("missing");
      },
      fetchImpl: (async () => new Response("{}")) as typeof fetch,
      writeDebug: () => undefined,
    },
    { agentDir: "/tmp/pi-agent", contextReserveTokens: 128_000 },
  );

  assert.equal(registered, false);
  assert.equal(calls.length, 0);
});
