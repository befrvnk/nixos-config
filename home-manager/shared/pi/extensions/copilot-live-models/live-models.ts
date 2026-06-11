import { COPILOT_HEADERS } from "./constants.ts";
import { mapCopilotModelsToPi } from "./model-mapping.ts";
import type {
  CopilotLiveModelsResponse,
  CopilotTokenInfo,
  PiProviderConfig,
  PiProviderModelConfig,
} from "./types.ts";

export async function fetchCopilotLiveModelsWithReserve(
  tokenInfo: CopilotTokenInfo,
  fetchImpl: typeof fetch,
  reserveTokens: number,
): Promise<PiProviderModelConfig[]> {
  const response = await fetchImpl(`${tokenInfo.apiBaseUrl}/models`, {
    headers: {
      ...COPILOT_HEADERS,
      Accept: "application/json",
      Authorization: `Bearer ${tokenInfo.token}`,
    },
  });

  if (!response.ok) {
    throw new Error(`GitHub Copilot live model fetch failed: ${response.status} ${response.statusText}`);
  }

  const payload = (await response.json()) as CopilotLiveModelsResponse;
  return mapCopilotModelsToPi(payload.data ?? [], reserveTokens);
}

export function buildProviderConfig(apiBaseUrl: string, models: PiProviderModelConfig[]): PiProviderConfig {
  return {
    name: "GitHub Copilot (live catalog)",
    baseUrl: apiBaseUrl,
    api: "openai-responses",
    // registerProvider() requires an apiKey when a models array is provided.
    // In normal use Pi's built-in GitHub Copilot OAuth storage wins; this env
    // fallback keeps the provider valid for headless/token-based sessions too.
    apiKey: "$COPILOT_GITHUB_TOKEN",
    headers: { ...COPILOT_HEADERS },
    models,
  };
}
