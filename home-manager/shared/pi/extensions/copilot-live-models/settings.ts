import path from "node:path";
import { DEFAULT_CONTEXT_RESERVE_TOKENS } from "./constants.ts";

export interface PiSettingsLike {
  compaction?: {
    reserveTokens?: unknown;
  };
}

export function parseContextReserveTokens(text: string): number {
  const parsed = JSON.parse(text) as PiSettingsLike;
  const value = parsed.compaction?.reserveTokens;
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : DEFAULT_CONTEXT_RESERVE_TOKENS;
}

export async function loadContextReserveTokens(
  agentDir: string,
  readTextFile: (path: string) => Promise<string>,
): Promise<number> {
  try {
    return parseContextReserveTokens(await readTextFile(path.join(agentDir, "settings.json")));
  } catch {
    return DEFAULT_CONTEXT_RESERVE_TOKENS;
  }
}
