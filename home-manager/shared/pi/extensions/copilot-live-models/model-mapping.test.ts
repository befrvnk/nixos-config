import assert from "node:assert/strict";
import test from "node:test";
import {
  calculatePiContextWindow,
  mapCopilotModelToPi,
  priceToDollarsPerMillion,
  resolvePiApi,
} from "./model-mapping.ts";
import type { CopilotLiveModel } from "./types.ts";

const gpt55: CopilotLiveModel = {
  id: "gpt-5.5",
  name: "GPT-5.5",
  vendor: "OpenAI",
  model_picker_enabled: true,
  supported_endpoints: ["/responses", "ws:/responses"],
  policy: { state: "enabled" },
  billing: {
    token_prices: {
      default: { context_max: 272_000, input_price: 500, output_price: 3000, cache_price: 50 },
      long_context: { context_max: 922_000, input_price: 1000, output_price: 4500, cache_price: 100 },
    },
  },
  capabilities: {
    type: "chat",
    limits: {
      max_context_window_tokens: 1_050_000,
      max_prompt_tokens: 922_000,
      max_output_tokens: 128_000,
      vision: {},
    },
    supports: {
      vision: true,
      reasoning_effort: ["none", "low", "medium", "high", "xhigh"],
    },
  },
};

test("priceToDollarsPerMillion converts Copilot cent-style prices to Pi dollar prices", () => {
  assert.equal(priceToDollarsPerMillion(1000), 10);
  assert.equal(priceToDollarsPerMillion(undefined), 0);
});

test("calculatePiContextWindow respects the prompt budget plus configured response reserve", () => {
  assert.equal(calculatePiContextWindow(gpt55, 128_000), 1_050_000);
  assert.equal(calculatePiContextWindow(gpt55, 16_384), 938_384);
  assert.equal(
    calculatePiContextWindow(
      {
        id: "gemini-3-flash-preview",
        capabilities: {
          limits: { max_context_window_tokens: 128_000, max_prompt_tokens: 128_000, max_output_tokens: 64_000 },
        },
      },
      128_000,
    ),
    256_000,
  );
});

test("mapCopilotModelToPi maps GPT-5.5 long-context Responses metadata", () => {
  const model = mapCopilotModelToPi(gpt55, 128_000);

  assert.equal(model?.id, "gpt-5.5");
  assert.equal(model?.api, "openai-responses");
  assert.equal(model?.contextWindow, 1_050_000);
  assert.equal(model?.maxTokens, 128_000);
  assert.deepEqual(model?.input, ["text", "image"]);
  assert.deepEqual(model?.cost, { input: 10, output: 45, cacheRead: 1, cacheWrite: 0 });
  assert.deepEqual(model?.thinkingLevelMap, {
    off: "none",
    minimal: "low",
    low: "low",
    medium: "medium",
    high: "high",
    xhigh: "xhigh",
  });
});

test("mapCopilotModelToPi maps Anthropic Messages models and adaptive thinking", () => {
  const model = mapCopilotModelToPi(
    {
      id: "claude-sonnet-4.6",
      name: "Claude Sonnet 4.6",
      vendor: "Anthropic",
      model_picker_enabled: true,
      supported_endpoints: ["/chat/completions", "/v1/messages"],
      capabilities: {
        type: "chat",
        limits: { max_context_window_tokens: 1_000_000, max_prompt_tokens: 936_000, max_output_tokens: 64_000 },
        supports: { adaptive_thinking: true, reasoning_effort: ["low", "medium", "high", "max"] },
      },
    },
    128_000,
  );

  assert.equal(model?.api, "anthropic-messages");
  assert.equal(model?.contextWindow, 1_064_000);
  assert.deepEqual(model?.compat, { forceAdaptiveThinking: true });
  assert.equal(model?.thinkingLevelMap?.xhigh, "max");
});

test("mapCopilotModelToPi maps chat-completions-only non-OpenAI models conservatively", () => {
  const model = mapCopilotModelToPi(
    {
      id: "gemini-3.1-pro-preview",
      name: "Gemini 3.1 Pro",
      vendor: "Google",
      model_picker_enabled: true,
      supported_endpoints: ["/chat/completions"],
      capabilities: {
        type: "chat",
        limits: { max_context_window_tokens: 1_000_000, max_prompt_tokens: 936_000, max_output_tokens: 64_000 },
        supports: { vision: true, reasoning_effort: ["low", "medium", "high"] },
      },
    },
    128_000,
  );

  assert.equal(model?.api, "openai-completions");
  assert.deepEqual(model?.compat, {
    supportsStore: false,
    supportsDeveloperRole: false,
    supportsReasoningEffort: false,
  });
});

test("resolvePiApi falls back to chat completions for older chat metadata", () => {
  assert.equal(resolvePiApi({ id: "gemini-2.5-pro", capabilities: { type: "chat" } }), "openai-completions");
});

test("mapCopilotModelToPi skips disabled, non-picker, and slash-delimited custom models", () => {
  assert.equal(mapCopilotModelToPi({ ...gpt55, policy: { state: "disabled" } }, 128_000), undefined);
  assert.equal(mapCopilotModelToPi({ ...gpt55, model_picker_enabled: false }, 128_000), undefined);
  assert.equal(mapCopilotModelToPi({ ...gpt55, id: "org/custom/model" }, 128_000), undefined);
});
