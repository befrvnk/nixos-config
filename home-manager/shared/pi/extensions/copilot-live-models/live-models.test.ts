import assert from "node:assert/strict";
import test from "node:test";
import { COPILOT_API_VERSION } from "./constants.ts";
import { buildProviderConfig, fetchCopilotLiveModelsWithReserve } from "./live-models.ts";
import type { CopilotLiveModel } from "./types.ts";

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

test("fetchCopilotLiveModelsWithReserve queries the 2026 model API and maps the result", async () => {
  let observedUrl = "";
  let observedApiVersion = "";
  let observedAuthorization = "";

  const models = await fetchCopilotLiveModelsWithReserve(
    { token: "copilot-token", apiBaseUrl: "https://api.enterprise.githubcopilot.com" },
    (async (url, init) => {
      const headers = init?.headers as Record<string, string>;
      observedUrl = String(url);
      observedApiVersion = headers["X-GitHub-Api-Version"];
      observedAuthorization = headers.Authorization;
      return new Response(JSON.stringify({ data: [liveModel] }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }) as typeof fetch,
    128_000,
  );

  assert.equal(observedUrl, "https://api.enterprise.githubcopilot.com/models");
  assert.equal(observedApiVersion, COPILOT_API_VERSION);
  assert.equal(observedAuthorization, "Bearer copilot-token");
  assert.equal(models[0]?.id, "gpt-5.5");
  assert.equal(models[0]?.contextWindow, 1_050_000);
});

test("buildProviderConfig registers a GitHub Copilot provider replacement", () => {
  const provider = buildProviderConfig("https://api.enterprise.githubcopilot.com", [
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
  ]);

  assert.equal(provider.baseUrl, "https://api.enterprise.githubcopilot.com");
  assert.equal(provider.apiKey, "$COPILOT_GITHUB_TOKEN");
  assert.equal(provider.headers?.["X-GitHub-Api-Version"], COPILOT_API_VERSION);
  assert.equal(provider.models?.[0]?.id, "gpt-5.5");
});
