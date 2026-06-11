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
  return process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
}

if (isMainModule()) {
  const ok = await refreshCopilotModelsJson();
  process.exitCode = ok ? 0 : 2;
}
