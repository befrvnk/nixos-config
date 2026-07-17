import { COPILOT_HEADERS } from "./constants.ts";
import { mapCopilotModelsToPi } from "./model-mapping.ts";
import type {
  CopilotLiveModelsResponse,
  CopilotTokenInfo,
  PiProviderModelConfig,
} from "./types.ts";

export async function fetchCopilotLiveModelsWithReserve(
  tokenInfo: CopilotTokenInfo,
  fetchImpl: typeof fetch,
  reserveTokens: number,
  signal?: AbortSignal,
): Promise<PiProviderModelConfig[]> {
  const response = await fetchImpl(`${tokenInfo.apiBaseUrl}/models`, {
    headers: {
      ...COPILOT_HEADERS,
      Accept: "application/json",
      Authorization: `Bearer ${tokenInfo.token}`,
    },
    signal,
  });

  if (!response.ok) {
    throw new Error(`GitHub Copilot live model fetch failed: ${response.status} ${response.statusText}`);
  }

  const payload = (await response.json()) as CopilotLiveModelsResponse;
  return mapCopilotModelsToPi(payload.data ?? [], reserveTokens);
}
