import assert from "node:assert/strict";
import test from "node:test";
import {
  fetchWithTimeout,
  parseFetchTimeoutMs,
  refreshCopilotLiveModels,
  registerCopilotLiveModels,
} from "./index.ts";
import type { CopilotLiveModel, CopilotLiveModelsProviderDeps, PiProviderConfig } from "./types.ts";

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

function createDeps(options: { getReserveTokens?: () => number } = {}): {
  deps: CopilotLiveModelsProviderDeps;
  urls: string[];
  signals: (AbortSignal | null)[];
} {
  const urls: string[] = [];
  const signals: (AbortSignal | null)[] = [];
  return {
    urls,
    signals,
    deps: {
      readTextFile: async (filePath) => {
        if (filePath.endsWith("settings.json")) {
          return JSON.stringify({ compaction: { reserveTokens: options.getReserveTokens?.() ?? 128_000 } });
        }
        throw new Error(`unexpected file: ${filePath}`);
      },
      fetchImpl: (async (url, init) => {
        urls.push(String(url));
        signals.push(init?.signal ?? null);
        return new Response(JSON.stringify({ data: [liveModel] }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }) as typeof fetch,
      writeDebug: () => undefined,
    },
  };
}

test("refreshCopilotLiveModels uses Pi's OAuth credential and live model endpoint", async () => {
  const { deps, urls, signals } = createDeps();
  const signal = new AbortController().signal;

  const models = await refreshCopilotLiveModels(
    {
      credential: { type: "oauth", access: ACCESS_TOKEN },
      allowNetwork: true,
      signal,
    },
    deps,
    128_000,
  );

  assert.deepEqual(urls, ["https://api.enterprise.githubcopilot.com/models"]);
  assert.equal(signals[0], signal);
  assert.equal(models[0]?.id, "gpt-5.5");
  assert.equal(models[0]?.contextWindow, 1_050_000);
});

test("registerCopilotLiveModels registers a refresh callback without fetching during the factory", async () => {
  const previousEnabled = process.env.PI_COPILOT_LIVE_MODELS;
  delete process.env.PI_COPILOT_LIVE_MODELS;

  try {
    const { deps, urls } = createDeps();
    const calls: Array<{ provider: string; config: PiProviderConfig }> = [];

    const registered = await registerCopilotLiveModels(
      {
        registerProvider(provider: string, config: PiProviderConfig) {
          calls.push({ provider, config });
        },
      } as any,
      deps,
      { agentDir: "/tmp/pi-agent" },
    );

    assert.equal(registered, true);
    assert.equal(urls.length, 0);
    assert.equal(calls.length, 1);
    assert.equal(calls[0]?.provider, "github-copilot");
    assert.equal(typeof calls[0]?.config.refreshModels, "function");

    const models = await calls[0]!.config.refreshModels!({
      credential: { type: "oauth", access: ACCESS_TOKEN },
      allowNetwork: true,
    });
    assert.equal(models[0]?.id, "gpt-5.5");
  } finally {
    if (previousEnabled === undefined) {
      delete process.env.PI_COPILOT_LIVE_MODELS;
    } else {
      process.env.PI_COPILOT_LIVE_MODELS = previousEnabled;
    }
  }
});

test("dynamic refresh reloads the compaction reserve setting", async () => {
  const previousEnabled = process.env.PI_COPILOT_LIVE_MODELS;
  delete process.env.PI_COPILOT_LIVE_MODELS;
  let reserveTokens = 1_000;

  try {
    const { deps } = createDeps({ getReserveTokens: () => reserveTokens });
    let config: PiProviderConfig | undefined;
    await registerCopilotLiveModels(
      { registerProvider: (_provider: string, value: PiProviderConfig) => { config = value; } } as any,
      deps,
      { agentDir: "/tmp/pi-agent" },
    );

    const context = { credential: { type: "oauth", access: ACCESS_TOKEN }, allowNetwork: true };
    assert.equal((await config!.refreshModels!(context))[0]?.contextWindow, 923_000);

    reserveTokens = 2_000;
    assert.equal((await config!.refreshModels!(context))[0]?.contextWindow, 924_000);
  } finally {
    if (previousEnabled === undefined) {
      delete process.env.PI_COPILOT_LIVE_MODELS;
    } else {
      process.env.PI_COPILOT_LIVE_MODELS = previousEnabled;
    }
  }
});

test("refreshCopilotLiveModels rejects offline and unauthenticated refreshes", async () => {
  const { deps } = createDeps();

  await assert.rejects(
    refreshCopilotLiveModels(
      { credential: { type: "oauth", access: ACCESS_TOKEN }, allowNetwork: false },
      deps,
      128_000,
    ),
    /requires network access/,
  );
  await assert.rejects(
    refreshCopilotLiveModels({ allowNetwork: true }, deps, 128_000),
    /OAuth credentials are unavailable/,
  );
});

test("fetchWithTimeout combines the caller signal with a timeout", async () => {
  const caller = new AbortController();
  let observedSignal: AbortSignal | undefined;
  const wrapped = fetchWithTimeout(
    (async (_url, init) => {
      observedSignal = init?.signal ?? undefined;
      return new Response("{}");
    }) as typeof fetch,
    5_000,
  );

  await wrapped("https://example.test", { signal: caller.signal });
  assert.ok(observedSignal instanceof AbortSignal);
  assert.notEqual(observedSignal, caller.signal);
  caller.abort();
  assert.equal(observedSignal?.aborted, true);
});

test("parseFetchTimeoutMs falls back for invalid values", () => {
  assert.equal(parseFetchTimeoutMs(undefined), 10_000);
  assert.equal(parseFetchTimeoutMs("0"), 10_000);
  assert.equal(parseFetchTimeoutMs("2500"), 2_500);
});

test("registerCopilotLiveModels can be disabled", async () => {
  const previous = process.env.PI_COPILOT_LIVE_MODELS;
  process.env.PI_COPILOT_LIVE_MODELS = "0";
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
      delete process.env.PI_COPILOT_LIVE_MODELS;
    } else {
      process.env.PI_COPILOT_LIVE_MODELS = previous;
    }
  }
});
