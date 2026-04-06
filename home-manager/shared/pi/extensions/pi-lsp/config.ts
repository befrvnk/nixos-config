import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import type { ExtensionConfig } from "./types.js";

export const CONFIG_PATH = process.env.PI_LSP_CONFIG ?? path.join(os.homedir(), ".pi/agent/pi-lsp.json");

export function loadConfig(): ExtensionConfig {
  if (!fs.existsSync(CONFIG_PATH)) {
    throw new Error(`Missing pi-lsp config: ${CONFIG_PATH}`);
  }

  const parsed = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8")) as ExtensionConfig;
  if (!parsed || typeof parsed !== "object" || !parsed.servers || typeof parsed.servers !== "object") {
    throw new Error(`Invalid pi-lsp config: ${CONFIG_PATH}`);
  }

  return parsed;
}

export function getCacheRoot(): string {
  if (process.platform === "darwin") return path.join(os.homedir(), "Library", "Caches", "pi-lsp");
  return path.join(os.homedir(), ".cache", "pi-lsp");
}
