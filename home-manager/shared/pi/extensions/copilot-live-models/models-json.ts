import path from "node:path";
import { COPILOT_PROVIDER } from "./constants.ts";
import { discoverCopilotProviderConfig } from "./index.ts";
import { loadContextReserveTokens } from "./settings.ts";
import type {
  CopilotModelsJsonWriterDeps,
  DiscoverOptions,
  PiModelsJson,
  PiProviderConfig,
} from "./types.ts";

export function modelsJsonPath(agentDir: string): string {
  return path.join(agentDir, "models.json");
}

export function stripJsonComments(text: string): string {
  let output = "";
  let inString = false;
  let escaped = false;
  let inLineComment = false;
  let inBlockComment = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]!;
    const next = text[index + 1];

    if (inLineComment) {
      if (char === "\n" || char === "\r") {
        inLineComment = false;
        output += char;
      }
      continue;
    }

    if (inBlockComment) {
      if (char === "*" && next === "/") {
        inBlockComment = false;
        index += 1;
      } else if (char === "\n" || char === "\r") {
        output += char;
      }
      continue;
    }

    if (inString) {
      output += char;
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
      output += char;
      continue;
    }

    if (char === "/" && next === "/") {
      inLineComment = true;
      index += 1;
      continue;
    }

    if (char === "/" && next === "*") {
      inBlockComment = true;
      index += 1;
      continue;
    }

    output += char;
  }

  return output;
}

export function parseModelsJson(text: string): PiModelsJson {
  const parsed = JSON.parse(stripJsonComments(text)) as PiModelsJson;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
  if (parsed.providers !== undefined && (typeof parsed.providers !== "object" || Array.isArray(parsed.providers))) {
    return {};
  }
  return parsed;
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
  let existing: PiModelsJson = {};
  try {
    existing = await loadExistingModelsJson(filePath, deps.readTextFile);
  } catch (error) {
    deps.writeDebug?.(`Ignoring unreadable existing models.json: ${error instanceof Error ? error.message : String(error)}`);
  }

  const merged = mergeCopilotProviderConfig(existing, providerConfig);

  await deps.ensureDir(path.dirname(filePath));
  await deps.writeTextFile(filePath, `${JSON.stringify(merged, null, 2)}\n`);
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
