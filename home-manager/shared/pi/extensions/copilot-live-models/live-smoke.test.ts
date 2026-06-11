import assert from "node:assert/strict";
import test from "node:test";
import { discoverCopilotProviderConfig, defaultAgentDir, defaultDeps } from "./index.ts";

const runLiveSmoke = process.env.PI_COPILOT_LIVE_MODELS_LIVE_TEST === "1";

test("live Copilot catalog exposes GPT-5.5 long-context metadata", { skip: !runLiveSmoke }, async () => {
  const provider = await discoverCopilotProviderConfig(defaultDeps(), {
    agentDir: defaultAgentDir(),
    contextReserveTokens: 128_000,
  });

  assert.ok(provider, "expected a live GitHub Copilot provider config");
  assert.equal(provider.baseUrl, "https://api.enterprise.githubcopilot.com");

  const gpt55 = provider.models?.find((model) => model.id === "gpt-5.5");
  assert.ok(gpt55, "expected gpt-5.5 in the live Copilot catalog");
  assert.equal(gpt55.api, "openai-responses");
  assert.equal(gpt55.maxTokens, 128_000);
  assert.ok(
    (gpt55.contextWindow ?? 0) >= 1_000_000,
    `expected GPT-5.5 long-context metadata, got ${gpt55.contextWindow}`,
  );
});
