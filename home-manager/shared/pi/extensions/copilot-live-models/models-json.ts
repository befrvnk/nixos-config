import path from "node:path";
import { COPILOT_PROVIDER } from "./constants.ts";
import { discoverCopilotProviderConfig } from "./index.ts";
import { parseJsonc } from "./jsonc.ts";
import { loadContextReserveTokens } from "./settings.ts";

export { stripJsonComments } from "./jsonc.ts";
import type {
  CopilotModelsJsonWriterDeps,
  DiscoverOptions,
  PiModelsJson,
  PiProviderConfig,
} from "./types.ts";

export function modelsJsonPath(agentDir: string): string {
  return path.join(agentDir, "models.json");
}

export function parseModelsJson(text: string): PiModelsJson {
  const parsed = parseJsonc(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new TypeError("models.json must contain a JSON object.");
  }

  const modelsJson = parsed as PiModelsJson;
  if (
    modelsJson.providers !== undefined
    && (!modelsJson.providers || typeof modelsJson.providers !== "object" || Array.isArray(modelsJson.providers))
  ) {
    throw new TypeError("models.json providers must be a JSON object when present.");
  }
  return modelsJson;
}

export async function loadExistingModelsJson(
  filePath: string,
  readTextFile: (path: string) => Promise<string>,
): Promise<PiModelsJson> {
  try {
    return parseModelsJson(await readTextFile(filePath));
  } catch (error) {
    const code = typeof error === "object" && error !== null && "code" in error ? String(error.code) : undefined;
    if (code === "ENOENT") return {};
    throw error;
  }
}

export function mergeCopilotProviderConfig(
  existing: PiModelsJson,
  providerConfig: PiProviderConfig,
): Required<PiModelsJson> {
  return {
    ...existing,
    providers: {
      ...(existing.providers ?? {}),
      [COPILOT_PROVIDER]: providerConfig,
    },
  };
}

export async function writeCopilotModelsJson(
  deps: CopilotModelsJsonWriterDeps,
  options: DiscoverOptions,
): Promise<boolean> {
  const providerConfig = await discoverCopilotProviderConfig(deps, options);
  if (!providerConfig) {
    deps.writeDebug?.("No live GitHub Copilot model catalog available; not updating models.json.");
    return false;
  }

  const filePath = modelsJsonPath(options.agentDir);
  let existing: PiModelsJson;
  try {
    existing = await loadExistingModelsJson(filePath, deps.readTextFile);
  } catch (error) {
    deps.writeDebug?.(`Preserving unreadable existing models.json: ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }

  const merged = mergeCopilotProviderConfig(existing, providerConfig);

  await deps.ensureDir(path.dirname(filePath));
  await deps.writeTextFileAtomic(filePath, `${JSON.stringify(merged, null, 2)}\n`);
  deps.writeDebug?.(`Updated ${filePath} with ${providerConfig.models?.length ?? 0} live GitHub Copilot models.`);
  return true;
}

export async function writeCopilotModelsJsonFromSettings(
  deps: CopilotModelsJsonWriterDeps,
  agentDir: string,
): Promise<boolean> {
  const contextReserveTokens = await loadContextReserveTokens(agentDir, deps.readTextFile);
  return writeCopilotModelsJson(deps, { agentDir, contextReserveTokens });
}
