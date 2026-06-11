import type {
  CopilotLiveModel,
  CopilotTokenPriceTier,
  PiApi,
  PiProviderModelConfig,
} from "./types.ts";

export function isUsableCopilotModel(model: CopilotLiveModel): boolean {
  if (!model.id) return false;
  // Copilot can expose organization custom models with slash-separated IDs. Pi's
  // provider/model shorthand also uses '/', so skip them until we handle aliases explicitly.
  if (model.id.includes("/")) return false;
  if (model.policy?.state === "disabled") return false;
  if (model.model_picker_enabled === false) return false;
  return true;
}

export function resolvePiApi(model: CopilotLiveModel): PiApi | undefined {
  const endpoints = new Set(model.supported_endpoints ?? []);

  if (endpoints.has("/responses") || endpoints.has("ws:/responses")) return "openai-responses";
  if (endpoints.has("/v1/messages")) return "anthropic-messages";
  if (endpoints.has("/chat/completions")) return "openai-completions";

  // Older Copilot model metadata may omit supported_endpoints even when the model is chat-compatible.
  if (model.capabilities?.type === "chat") return "openai-completions";

  return undefined;
}

export function selectPricingTier(model: CopilotLiveModel): CopilotTokenPriceTier | undefined {
  const prices = model.billing?.token_prices;
  return prices?.long_context ?? prices?.default;
}

export function priceToDollarsPerMillion(value: number | undefined): number {
  return value === undefined ? 0 : value / 100;
}

export function calculatePiContextWindow(model: CopilotLiveModel, reserveTokens: number): number {
  const limits = model.capabilities?.limits;
  const maxContext = limits?.max_context_window_tokens;
  const maxPrompt = limits?.max_prompt_tokens;

  // Pi subtracts the global compaction reserve from contextWindow to decide
  // when to compact. Copilot's live catalog exposes an explicit prompt budget,
  // so make Pi's effective prompt threshold equal that budget. maxTokens below
  // still caps the requested response size.
  if (maxPrompt) return maxPrompt + reserveTokens;
  return maxContext ?? 128_000;
}

export function buildThinkingLevelMap(
  model: CopilotLiveModel,
): PiProviderModelConfig["thinkingLevelMap"] | undefined {
  const efforts = model.capabilities?.supports?.reasoning_effort;
  if (!Array.isArray(efforts) || efforts.length === 0) return undefined;

  const supported = new Set(efforts);
  return {
    off: supported.has("none") ? "none" : null,
    minimal: supported.has("minimal") ? "minimal" : supported.has("low") ? "low" : null,
    low: supported.has("low") ? "low" : null,
    medium: supported.has("medium") ? "medium" : null,
    high: supported.has("high") ? "high" : null,
    xhigh: supported.has("xhigh") ? "xhigh" : supported.has("max") ? "max" : null,
  };
}

export function buildCompat(model: CopilotLiveModel, api: PiApi): Record<string, unknown> | undefined {
  if (api === "anthropic-messages" && model.capabilities?.supports?.adaptive_thinking) {
    return { forceAdaptiveThinking: true };
  }

  if (api === "openai-completions") {
    const vendor = model.vendor?.toLowerCase() ?? "";
    const isOpenAiLike = vendor.includes("openai") || model.id?.startsWith("gpt-");
    if (!isOpenAiLike) {
      return {
        supportsStore: false,
        supportsDeveloperRole: false,
        supportsReasoningEffort: false,
      };
    }
  }

  return undefined;
}

export function mapCopilotModelToPi(
  model: CopilotLiveModel,
  reserveTokens: number,
): PiProviderModelConfig | undefined {
  if (!isUsableCopilotModel(model)) return undefined;

  const api = resolvePiApi(model);
  if (!api) return undefined;

  const tier = selectPricingTier(model);
  const limits = model.capabilities?.limits;
  const thinkingLevelMap = buildThinkingLevelMap(model);
  const input: ("text" | "image")[] = model.capabilities?.supports?.vision ? ["text", "image"] : ["text"];

  return {
    id: model.id!,
    name: model.name ?? model.id!,
    api,
    reasoning: thinkingLevelMap !== undefined,
    thinkingLevelMap,
    input,
    cost: {
      input: priceToDollarsPerMillion(tier?.input_price),
      output: priceToDollarsPerMillion(tier?.output_price),
      cacheRead: priceToDollarsPerMillion(tier?.cache_price),
      cacheWrite: 0,
    },
    contextWindow: calculatePiContextWindow(model, reserveTokens),
    maxTokens: limits?.max_output_tokens ?? 16_384,
    compat: buildCompat(model, api),
  };
}

export function mapCopilotModelsToPi(
  models: CopilotLiveModel[],
  reserveTokens: number,
): PiProviderModelConfig[] {
  return models
    .map((model) => mapCopilotModelToPi(model, reserveTokens))
    .filter((model): model is PiProviderModelConfig => model !== undefined)
    .sort((a, b) => a.id.localeCompare(b.id));
}
