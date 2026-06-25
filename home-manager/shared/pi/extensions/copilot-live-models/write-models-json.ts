import { realpathSync } from "node:fs";
import fs from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { defaultAgentDir, defaultDeps } from "./index.ts";
import { writeCopilotModelsJsonFromSettings } from "./models-json.ts";
import type { CopilotModelsJsonWriterDeps } from "./types.ts";

export function defaultWriterDeps(): CopilotModelsJsonWriterDeps {
  const deps = defaultDeps();

  return {
    ...deps,
    ensureDir: (dirPath) => fs.mkdir(dirPath, { recursive: true }).then(() => undefined),
    writeTextFile: (filePath, text) => fs.writeFile(filePath, text, "utf8"),
  };
}

export async function refreshCopilotModelsJson(
  deps: CopilotModelsJsonWriterDeps = defaultWriterDeps(),
  agentDir: string = defaultAgentDir(),
): Promise<boolean> {
  if (process.env.PI_COPILOT_LIVE_MODELS === "0") return false;

  try {
    return await writeCopilotModelsJsonFromSettings(deps, agentDir);
  } catch (error) {
    deps.writeDebug?.(`Failed to update GitHub Copilot models.json: ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
}

function isMainModule(): boolean {
  const mainPath = process.argv[1];
  if (mainPath === undefined) return false;

  if (import.meta.url === pathToFileURL(mainPath).href) return true;

  try {
    return import.meta.url === pathToFileURL(realpathSync(mainPath)).href;
  } catch {
    return false;
  }
}

if (isMainModule()) {
  const ok = await refreshCopilotModelsJson();
  process.exitCode = ok ? 0 : 2;
}
