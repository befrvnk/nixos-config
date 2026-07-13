import { createHash } from "node:crypto";
import type {
  SubagentRunState,
  SubagentTaskInput,
  SubagentTaskResult,
} from "./types.js";

export const EXPLORE_CACHE_SCHEMA_VERSION = 1;
export const EXPLORE_SUCCESS_TTL_MS = 5 * 60_000;
export const EXPLORE_FAILURE_COOLDOWN_MS = 30_000;
export const EXPLORE_SIMILARITY_THRESHOLD = 0.88;
export const MAX_EXPLORE_CACHE_ENTRIES = 10;
export const MAX_ACTIVE_EXPLORE_RUNS = 2;
export const MAX_EXPLORE_SESSION_TOKENS = 1_000_000;

export type ExploreCacheRecord = {
  key: string;
  workspaceRevision: string;
  tasks: SubagentTaskInput[];
  run: SubagentRunState;
  results: SubagentTaskResult[];
  content: string;
  completedAt: number;
};

export type ExploreCacheMatch = {
  record: ExploreCacheRecord;
  kind: "exact" | "similar";
  similarity: number;
};

function normalizeExactTask(text: string): string {
  return text
    .replace(/\r\n?/gu, "\n")
    .split("\n")
    .map((line) => line.replace(/[ \t]+$/gu, ""))
    .join("\n")
    .trim();
}

function taskFingerprintValue(task: SubagentTaskInput) {
  return {
    task: normalizeExactTask(task.task),
    cwd: task.cwd ?? "",
    intent: task.intent ?? "",
    model: task.model ?? "",
    thinkingLevel: task.thinkingLevel ?? "",
  };
}

export function createExplorationKey(
  tasks: SubagentTaskInput[],
  workspaceRevision: string,
): string {
  const serialized = JSON.stringify({
    schemaVersion: EXPLORE_CACHE_SCHEMA_VERSION,
    workflow: "explore",
    workspaceRevision,
    tasks: tasks.map(taskFingerprintValue),
  });
  return createHash("sha256").update(serialized).digest("hex");
}

const PROCEDURAL_BOILERPLATE = [
  /\bfresh(?:ly)?\s+(?:and\s+)?independent\b/giu,
  /\bdo not rely on (?:the )?(?:prior|previous|earlier) (?:analysis|work|results?)\b/giu,
  /\bwithout relying on (?:the )?(?:prior|previous|earlier) (?:analysis|work|results?)\b/giu,
  /\bstart (?:again )?from scratch\b/giu,
];

function similarityTokens(text: string): Set<string> {
  let normalized = text.toLowerCase();
  for (const pattern of PROCEDURAL_BOILERPLATE) normalized = normalized.replace(pattern, " ");
  return new Set(
    normalized.match(/[\p{L}\p{N}_]+(?:[./:@-][\p{L}\p{N}_]+)*/gu) ?? [],
  );
}

function jaccard(left: Set<string>, right: Set<string>): number {
  if (left.size === 0 && right.size === 0) return 1;
  let intersection = 0;
  for (const token of left) if (right.has(token)) intersection += 1;
  return intersection / (left.size + right.size - intersection);
}

export function explorationSimilarity(
  requested: SubagentTaskInput[],
  previous: SubagentTaskInput[],
): number {
  if (requested.length !== previous.length || requested.length === 0) return 0;

  let total = 0;
  for (let index = 0; index < requested.length; index += 1) {
    const left = requested[index]!;
    const right = previous[index]!;
    if (
      left.cwd !== right.cwd
      || left.model !== right.model
      || left.thinkingLevel !== right.thinkingLevel
    ) {
      return 0;
    }
    total += jaccard(similarityTokens(left.task), similarityTokens(right.task));
  }
  return total / requested.length;
}

export function findReusableExploration(
  records: Iterable<ExploreCacheRecord>,
  tasks: SubagentTaskInput[],
  key: string,
  workspaceRevision: string,
  now = Date.now(),
): ExploreCacheMatch | undefined {
  let bestSimilar: ExploreCacheMatch | undefined;

  for (const record of records) {
    const age = now - record.completedAt;
    if (record.key === key) {
      const ttl = record.run.state === "success"
        ? EXPLORE_SUCCESS_TTL_MS
        : EXPLORE_FAILURE_COOLDOWN_MS;
      if (age >= 0 && age <= ttl) return { record, kind: "exact", similarity: 1 };
      continue;
    }
    if (
      record.run.state !== "success"
      || record.workspaceRevision !== workspaceRevision
      || age < 0
      || age > EXPLORE_SUCCESS_TTL_MS
    ) {
      continue;
    }
    const similarity = explorationSimilarity(tasks, record.tasks);
    if (
      similarity >= EXPLORE_SIMILARITY_THRESHOLD
      && (!bestSimilar || similarity > bestSimilar.similarity)
    ) {
      bestSimilar = { record, kind: "similar", similarity };
    }
  }

  return bestSimilar;
}

export function rememberExploration(
  records: Map<string, ExploreCacheRecord>,
  record: ExploreCacheRecord,
): void {
  records.delete(record.key);
  records.set(record.key, record);
  while (records.size > MAX_EXPLORE_CACHE_ENTRIES) {
    const oldest = records.keys().next().value as string | undefined;
    if (!oldest) break;
    records.delete(oldest);
  }
}

export function totalExploreTokens(records: Iterable<ExploreCacheRecord>): number {
  let total = 0;
  for (const record of records) {
    for (const task of record.run.tasks) total += Math.max(0, task.tokenCount || 0);
  }
  return total;
}

export function parseFreshExploreArgs(args: string): {
  intent?: "fast" | "balanced" | "deep";
  task?: string;
} {
  const trimmed = args.trim();
  if (!trimmed) return {};
  const match = trimmed.match(/^(fast|balanced|deep)\s+([\s\S]+)$/u);
  return match
    ? { intent: match[1] as "fast" | "balanced" | "deep", task: match[2]!.trim() }
    : { task: trimmed };
}
