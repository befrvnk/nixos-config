import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { COPILOT_PROVIDER, DEFAULT_FETCH_TIMEOUT_MS } from "./constants.ts";
import { loadCopilotCredentials, resolveCopilotToken } from "./auth.ts";
import { buildProviderConfig, fetchCopilotLiveModelsWithReserve } from "./live-models.ts";
import { loadContextReserveTokens } from "./settings.ts";
import type { CopilotLiveModelsProviderDeps, DiscoverOptions, PiProviderConfig } from "./types.ts";

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
    const signal = init?.signal ?? AbortSignal.timeout(timeoutMs);
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
    now: () => Date.now(),
  };
}

export async function discoverCopilotProviderConfig(
  deps: CopilotLiveModelsProviderDeps,
  options: DiscoverOptions,
): Promise<PiProviderConfig | undefined> {
  const credentials = await loadCopilotCredentials(options.agentDir, deps.readTextFile);
  const tokenInfo = await resolveCopilotToken(credentials, deps.fetchImpl, deps.now());
  if (!tokenInfo) return undefined;

  const models = await fetchCopilotLiveModelsWithReserve(tokenInfo, deps.fetchImpl, options.contextReserveTokens);
  if (models.length === 0) return undefined;

  return buildProviderConfig(tokenInfo.apiBaseUrl, models);
}

export async function registerCopilotLiveModels(
  pi: Pick<ExtensionAPI, "registerProvider">,
  deps: CopilotLiveModelsProviderDeps = defaultDeps(),
  options: Partial<DiscoverOptions> = {},
): Promise<boolean> {
  if (process.env.PI_COPILOT_LIVE_MODELS === "0") return false;
  if (process.env.PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION === "1") return false;

  const agentDir = options.agentDir ?? defaultAgentDir();
  const contextReserveTokens =
    options.contextReserveTokens ?? (await loadContextReserveTokens(agentDir, deps.readTextFile));

  try {
    const providerConfig = await discoverCopilotProviderConfig(deps, { agentDir, contextReserveTokens });
    if (!providerConfig) {
      deps.writeDebug?.("No live GitHub Copilot model catalog available; keeping Pi's built-in catalog.");
      return false;
    }

    pi.registerProvider(COPILOT_PROVIDER, providerConfig as never);
    deps.writeDebug?.(`Registered ${providerConfig.models?.length ?? 0} live GitHub Copilot models.`);
    return true;
  } catch (error) {
    deps.writeDebug?.(`Failed to register live GitHub Copilot models: ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
}

export default async function (pi: ExtensionAPI) {
  await registerCopilotLiveModels(pi);
}
