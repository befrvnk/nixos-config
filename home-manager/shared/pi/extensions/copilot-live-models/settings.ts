import path from "node:path";
import { DEFAULT_CONTEXT_RESERVE_TOKENS } from "./constants.ts";
import { parseJsonc } from "./jsonc.ts";
import { positiveSafeIntegerOr } from "./token-validation.ts";

export interface PiSettingsLike {
  compaction?: {
    reserveTokens?: unknown;
  };
}

export function parseContextReserveTokens(text: string): number {
  const parsed = parseJsonc(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return DEFAULT_CONTEXT_RESERVE_TOKENS;
  }

  const compaction = (parsed as PiSettingsLike).compaction;
  if (!compaction || typeof compaction !== "object" || Array.isArray(compaction)) {
    return DEFAULT_CONTEXT_RESERVE_TOKENS;
  }

  return positiveSafeIntegerOr(compaction.reserveTokens, DEFAULT_CONTEXT_RESERVE_TOKENS);
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
