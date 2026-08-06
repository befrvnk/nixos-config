import { DEFAULT_CONTEXT_RESERVE_TOKENS } from "./constants.ts";
import { isPositiveSafeInteger, positiveSafeIntegerOr } from "./token-validation.ts";
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
  if (model.model_picker_enabled !== true) return false;
  if (model.capabilities?.supports?.tool_calls === false) return false;
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
  return prices?.default ?? prices?.long_context;
}

export function priceToDollarsPerMillion(value: number | undefined): number {
  return value === undefined ? 0 : value / 100;
}

export function calculatePiContextWindow(model: CopilotLiveModel, reserveTokens: number): number {
  const limits = model.capabilities?.limits;
  const maxContext = isPositiveSafeInteger(limits?.max_context_window_tokens)
    ? limits.max_context_window_tokens
    : undefined;
  if (maxContext !== undefined) return maxContext;

  const prices = model.billing?.token_prices;
  const promptLimits = [
    limits?.max_prompt_tokens,
    prices?.long_context?.context_max,
    prices?.default?.context_max,
  ].filter(isPositiveSafeInteger);
  if (promptLimits.length === 0) return 128_000;
  const promptLimit = Math.max(...promptLimits);

  const responseAllowance = isPositiveSafeInteger(limits?.max_output_tokens)
    ? limits.max_output_tokens
    : positiveSafeIntegerOr(reserveTokens, DEFAULT_CONTEXT_RESERVE_TOKENS);

  // Pi's contextWindow is the combined prompt and response capacity. Prefer the
  // catalog's explicit combined limit above; otherwise reconstruct it from the
  // largest advertised prompt tier and the model's output allowance.
  return promptLimit > Number.MAX_SAFE_INTEGER - responseAllowance
    ? Number.MAX_SAFE_INTEGER
    : promptLimit + responseAllowance;
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

  const contextWindow = calculatePiContextWindow(model, reserveTokens);
  const maxTokens = Math.min(
    positiveSafeIntegerOr(limits?.max_output_tokens, 16_384),
    contextWindow,
  );

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
    contextWindow,
    maxTokens,
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
