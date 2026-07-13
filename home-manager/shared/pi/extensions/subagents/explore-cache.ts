import { createHash } from "node:crypto";
import type {
  SubagentRunState,
  SubagentTaskInput,
  SubagentTaskResult,
} from "./types.js";

export const EXPLORE_CACHE_SCHEMA_VERSION = 1;
export const EXPLORE_CACHE_ENTRY_TYPE = "subagent-explore-cache";
export const WORKSPACE_GENERATION_ENTRY_TYPE = "subagent-workspace-generation";
export const EXPLORE_SUCCESS_TTL_MS = 5 * 60_000;
export const EXPLORE_FAILURE_COOLDOWN_MS = 30_000;
export const EXPLORE_SIMILARITY_THRESHOLD = 0.88;
export const MAX_EXPLORE_CACHE_ENTRIES = 10;
export const MAX_EXPLORE_CACHE_BYTES = 2 * 1024 * 1024;
export const MAX_ACTIVE_EXPLORE_RUNS = 1;
export const MAX_EXPLORE_SESSION_TOKENS = 1_000_000;

export type ExploreCacheMetadata = {
  schemaVersion: number;
  key: string;
  workspaceRevision: string;
  tasks: SubagentTaskInput[];
  completedAt: number;
  launched: boolean;
};

export type ExploreCacheRecord = {
  key: string;
  workspaceRevision: string;
  tasks: SubagentTaskInput[];
  run: SubagentRunState;
  results: SubagentTaskResult[];
  content: string;
  completedAt: number;
};

export type ActiveExploration = {
  key: string;
  controller: AbortController;
  promise: Promise<ExploreCacheRecord>;
  waiters: number;
  settled: boolean;
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

export function createExploreCacheMetadata(
  record: ExploreCacheRecord,
  launched: boolean,
): ExploreCacheMetadata {
  return {
    schemaVersion: EXPLORE_CACHE_SCHEMA_VERSION,
    key: record.key,
    workspaceRevision: record.workspaceRevision,
    tasks: record.tasks,
    completedAt: record.completedAt,
    launched,
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

function recordBytes(record: ExploreCacheRecord): number {
  return Buffer.byteLength(JSON.stringify(record), "utf8");
}

export function rememberExploration(
  records: Map<string, ExploreCacheRecord>,
  record: ExploreCacheRecord,
): void {
  records.delete(record.key);
  if (recordBytes(record) > MAX_EXPLORE_CACHE_BYTES) return;
  records.set(record.key, record);
  let totalBytes = [...records.values()].reduce((total, item) => total + recordBytes(item), 0);
  while (
    records.size > MAX_EXPLORE_CACHE_ENTRIES
    || totalBytes > MAX_EXPLORE_CACHE_BYTES
  ) {
    const oldest = records.keys().next().value as string | undefined;
    if (!oldest) break;
    const removed = records.get(oldest);
    records.delete(oldest);
    if (removed) totalBytes -= recordBytes(removed);
  }
}

function textFromToolContent(content: unknown): string {
  if (!Array.isArray(content)) return "";
  return content
    .filter((item): item is { type: "text"; text: string } =>
      Boolean(item && typeof item === "object" && item.type === "text" && typeof item.text === "string")
    )
    .map((item) => item.text)
    .join("\n");
}

function cacheRecordFromToolResult(message: any): ExploreCacheRecord | undefined {
  if (message?.role !== "toolResult" || message.toolName !== "explore" || message.isError) return undefined;
  const details = message.details as {
    cache?: ExploreCacheMetadata;
    run?: SubagentRunState;
    results?: unknown;
  } | undefined;
  const cache = details?.cache;
  if (
    cache?.schemaVersion !== EXPLORE_CACHE_SCHEMA_VERSION
    || !cache.key
    || !cache.workspaceRevision
    || !Array.isArray(cache.tasks)
    || !details?.run
    || !Array.isArray(details.results)
  ) {
    return undefined;
  }
  return {
    key: cache.key,
    workspaceRevision: cache.workspaceRevision,
    tasks: cache.tasks,
    run: details.run,
    results: details.results as SubagentTaskResult[],
    content: textFromToolContent(message.content),
    completedAt: cache.completedAt,
  };
}

export function restoreExploreCacheState(entries: readonly any[]): {
  records: Map<string, ExploreCacheRecord>;
  runs: SubagentRunState[];
  tokens: number;
  workspaceGeneration: number;
} {
  const records = new Map<string, ExploreCacheRecord>();
  const runs: SubagentRunState[] = [];
  const restoredRunIds = new Set<string>();
  let tokens = 0;
  let workspaceGeneration = 0;

  for (const entry of entries) {
    if (entry?.type === "custom" && entry.customType === WORKSPACE_GENERATION_ENTRY_TYPE) {
      const generation = entry.data?.generation;
      if (typeof generation === "number" && Number.isSafeInteger(generation)) {
        workspaceGeneration = Math.max(workspaceGeneration, generation);
      }
      continue;
    }

    let record: ExploreCacheRecord | undefined;
    let launched = false;
    if (entry?.type === "message") {
      record = cacheRecordFromToolResult(entry.message);
      launched = entry.message?.details?.cache?.launched === true;
    } else if (entry?.type === "custom" && entry.customType === EXPLORE_CACHE_ENTRY_TYPE) {
      record = entry.data?.record as ExploreCacheRecord | undefined;
      launched = entry.data?.launched === true;
    }
    if (!record?.key || !record.run?.runId || !launched) continue;

    rememberExploration(records, record);
    if (!restoredRunIds.has(record.run.runId)) {
      restoredRunIds.add(record.run.runId);
      runs.unshift(record.run);
      for (const task of record.run.tasks) tokens += Math.max(0, task.tokenCount || 0);
    }
  }

  return { records, runs, tokens, workspaceGeneration };
}

export function subscribeToActiveExploration(
  active: ActiveExploration,
  signal?: AbortSignal,
): Promise<ExploreCacheRecord> {
  active.waiters += 1;
  return new Promise<ExploreCacheRecord>((resolve, reject) => {
    let finished = false;
    const cleanup = () => {
      if (finished) return;
      finished = true;
      signal?.removeEventListener("abort", abort);
      active.waiters = Math.max(0, active.waiters - 1);
      if (active.waiters === 0 && !active.settled) {
        active.controller.abort(new Error("All exploration waiters cancelled."));
      }
    };
    const abort = () => {
      cleanup();
      reject(signal?.reason ?? new Error("Exploration cancelled."));
    };
    if (signal?.aborted) {
      abort();
      return;
    }
    signal?.addEventListener("abort", abort, { once: true });
    active.promise.then(
      (value) => {
        if (finished) return;
        cleanup();
        resolve(value);
      },
      (error) => {
        if (finished) return;
        cleanup();
        reject(error);
      },
    );
  });
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
