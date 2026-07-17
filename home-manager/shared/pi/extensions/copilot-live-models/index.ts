import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getApiBaseUrlFromCopilotCredential } from "./auth.ts";
import { COPILOT_PROVIDER, DEFAULT_FETCH_TIMEOUT_MS } from "./constants.ts";
import { fetchCopilotLiveModelsWithReserve } from "./live-models.ts";
import { loadContextReserveTokens } from "./settings.ts";
import type {
  CopilotLiveModelsProviderDeps,
  CopilotRefreshModelsContext,
  PiProviderConfig,
  PiProviderModelConfig,
} from "./types.ts";

export function defaultAgentDir(): string {
  return process.env.PI_CODING_AGENT_DIR ?? path.join(os.homedir(), ".pi", "agent");
}

export function parseFetchTimeoutMs(value: string | undefined): number {
  if (value === undefined || value.trim() === "") return DEFAULT_FETCH_TIMEOUT_MS;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_FETCH_TIMEOUT_MS;
}

export function fetchWithTimeout(baseFetch: typeof fetch, timeoutMs: number): typeof fetch {
  return ((input, init) => {
    const timeoutSignal = AbortSignal.timeout(timeoutMs);
    const signal = init?.signal
      ? AbortSignal.any([init.signal, timeoutSignal])
      : timeoutSignal;
    return baseFetch(input, { ...init, signal });
  }) as typeof fetch;
}

export function defaultDeps(): CopilotLiveModelsProviderDeps {
  return {
    fetchImpl: fetchWithTimeout(fetch, parseFetchTimeoutMs(process.env.PI_COPILOT_LIVE_MODELS_TIMEOUT_MS)),
    readTextFile: (filePath) => fs.readFile(filePath, "utf8"),
    writeDebug: (message) => {
      if (process.env.PI_COPILOT_LIVE_MODELS_DEBUG === "1") {
        console.error(`[copilot-live-models] ${message}`);
      }
    },
  };
}

export async function refreshCopilotLiveModels(
  context: CopilotRefreshModelsContext,
  deps: CopilotLiveModelsProviderDeps,
  contextReserveTokens: number,
): Promise<PiProviderModelConfig[]> {
  if (!context.allowNetwork) {
    throw new Error("GitHub Copilot live model refresh requires network access.");
  }
  if (context.credential?.type !== "oauth" || !context.credential.access) {
    throw new Error("GitHub Copilot OAuth credentials are unavailable.");
  }

  const apiBaseUrl = getApiBaseUrlFromCopilotCredential(context.credential);

  const models = await fetchCopilotLiveModelsWithReserve(
    { token: context.credential.access, apiBaseUrl },
    deps.fetchImpl,
    contextReserveTokens,
    context.signal,
  );
  if (models.length === 0) {
    throw new Error("GitHub Copilot returned no usable live models.");
  }

  deps.writeDebug?.(`Discovered ${models.length} live GitHub Copilot models.`);
  return models;
}

export async function registerCopilotLiveModels(
  pi: Pick<ExtensionAPI, "registerProvider">,
  deps: CopilotLiveModelsProviderDeps = defaultDeps(),
  options: { agentDir?: string; contextReserveTokens?: number } = {},
): Promise<boolean> {
  if (process.env.PI_COPILOT_LIVE_MODELS === "0") return false;

  const agentDir = options.agentDir ?? defaultAgentDir();

  const providerConfig: PiProviderConfig = {
    refreshModels: async (context) => {
      try {
        const contextReserveTokens =
          options.contextReserveTokens ?? (await loadContextReserveTokens(agentDir, deps.readTextFile));
        return await refreshCopilotLiveModels(context, deps, contextReserveTokens);
      } catch (error) {
        deps.writeDebug?.(
          `Failed to refresh live GitHub Copilot models: ${error instanceof Error ? error.message : String(error)}`,
        );
        throw error;
      }
    },
  };

  pi.registerProvider(COPILOT_PROVIDER, providerConfig as never);
  deps.writeDebug?.("Registered dynamic GitHub Copilot model refresh.");
  return true;
}

export default async function (pi: ExtensionAPI) {
  await registerCopilotLiveModels(pi);
}
