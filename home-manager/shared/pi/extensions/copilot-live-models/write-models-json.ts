import { randomUUID } from "node:crypto";
import { realpathSync } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { defaultAgentDir, defaultDeps } from "./index.ts";
import { writeCopilotModelsJsonFromSettings } from "./models-json.ts";
import type { CopilotModelsJsonWriterDeps } from "./types.ts";

interface AtomicWriteOperations {
  open: typeof fs.open;
  rename: typeof fs.rename;
  unlink: typeof fs.unlink;
}

export async function atomicWriteTextFile(
  filePath: string,
  text: string,
  overrides: Partial<AtomicWriteOperations> = {},
): Promise<void> {
  const operations: AtomicWriteOperations = {
    open: overrides.open ?? fs.open,
    rename: overrides.rename ?? fs.rename,
    unlink: overrides.unlink ?? fs.unlink,
  };
  const tempPath = path.join(
    path.dirname(filePath),
    `.${path.basename(filePath)}.${process.pid}.${randomUUID()}.tmp`,
  );
  let handle: Awaited<ReturnType<typeof fs.open>> | undefined;
  let renamed = false;

  try {
    handle = await operations.open(tempPath, "wx", 0o600);
    await handle.writeFile(text, "utf8");
    await handle.sync();
    await handle.close();
    handle = undefined;
    await operations.rename(tempPath, filePath);
    renamed = true;
  } finally {
    if (handle) await handle.close().catch(() => undefined);
    if (!renamed) await operations.unlink(tempPath).catch(() => undefined);
  }
}

export function defaultWriterDeps(): CopilotModelsJsonWriterDeps {
  const deps = defaultDeps();

  return {
    ...deps,
    ensureDir: (dirPath) => fs.mkdir(dirPath, { recursive: true }).then(() => undefined),
    writeTextFileAtomic: atomicWriteTextFile,
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
