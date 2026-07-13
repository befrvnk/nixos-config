import assert from "node:assert/strict";
import test from "node:test";
import {
  createExploreCacheMetadata,
  createExplorationKey,
  EXPLORE_CACHE_ENTRY_TYPE,
  MAX_EXPLORE_CACHE_BYTES,
  explorationSimilarity,
  EXPLORE_FAILURE_COOLDOWN_MS,
  EXPLORE_SUCCESS_TTL_MS,
  findReusableExploration,
  parseFreshExploreArgs,
  rememberExploration,
  restoreExploreCacheState,
  subscribeToActiveExploration,
  type ActiveExploration,
  type ExploreCacheRecord,
  WORKSPACE_GENERATION_ENTRY_TYPE,
} from "./explore-cache.ts";
import type { SubagentRunState, SubagentTaskInput } from "./types.ts";

function task(overrides: Partial<SubagentTaskInput> = {}): SubagentTaskInput {
  return {
    task: "Inspect the repository architecture and summarize findings.",
    cwd: "/repo",
    intent: "balanced",
    model: "github-copilot/model",
    thinkingLevel: "medium",
    ...overrides,
  };
}

function record(overrides: Partial<ExploreCacheRecord> = {}): ExploreCacheRecord {
  const tasks = overrides.tasks ?? [task()];
  const workspaceRevision = overrides.workspaceRevision ?? "revision-1";
  const run: SubagentRunState = overrides.run ?? {
    workflow: "explore",
    runId: "run-1",
    mode: "single",
    state: "success",
    startedAt: 1,
    endedAt: 2,
    tasks: [],
  };
  return {
    key: createExplorationKey(tasks, workspaceRevision),
    workspaceRevision,
    tasks,
    run,
    results: [],
    content: "cached findings",
    completedAt: 10_000,
    ...overrides,
  };
}

test("createExplorationKey normalizes line endings but preserves meaningful case", () => {
  const base = task({ task: "Inspect Foo\r\ncarefully   " });
  const normalized = task({ task: "Inspect Foo\ncarefully" });
  const changedCase = task({ task: "Inspect foo\ncarefully" });
  assert.equal(createExplorationKey([base], "rev"), createExplorationKey([normalized], "rev"));
  assert.notEqual(createExplorationKey([base], "rev"), createExplorationKey([changedCase], "rev"));
  assert.notEqual(createExplorationKey([base], "rev"), createExplorationKey([base], "other-rev"));
});

test("explorationSimilarity ignores narrow rerun boilerplate but respects execution scope", () => {
  const original = [task()];
  const repeated = [task({ task: "Fresh independent: inspect the repository architecture and summarize findings. Do not rely on prior analysis." })];
  assert.ok(explorationSimilarity(repeated, original) >= 0.88);
  assert.equal(explorationSimilarity([task({ cwd: "/other" })], original), 0);
  assert.equal(explorationSimilarity([task({ model: "other/model" })], original), 0);
});

test("findReusableExploration applies success TTL and failure cooldown", () => {
  const success = record();
  assert.equal(
    findReusableExploration([success], success.tasks, success.key, success.workspaceRevision, success.completedAt + EXPLORE_SUCCESS_TTL_MS)?.record,
    success,
  );
  assert.equal(
    findReusableExploration([success], success.tasks, success.key, success.workspaceRevision, success.completedAt + EXPLORE_SUCCESS_TTL_MS + 1),
    undefined,
  );

  const failed = record({ run: { ...success.run, state: "error" } });
  assert.equal(
    findReusableExploration([failed], failed.tasks, failed.key, failed.workspaceRevision, failed.completedAt + EXPLORE_FAILURE_COOLDOWN_MS)?.record,
    failed,
  );
  assert.equal(
    findReusableExploration([failed], failed.tasks, failed.key, failed.workspaceRevision, failed.completedAt + EXPLORE_FAILURE_COOLDOWN_MS + 1),
    undefined,
  );
});

test("findReusableExploration reports conservative near duplicates", () => {
  const previous = record();
  const requested = [task({ task: "Fresh independent inspect the repository architecture and summarize findings" })];
  const key = createExplorationKey(requested, previous.workspaceRevision);
  const match = findReusableExploration([previous], requested, key, previous.workspaceRevision, previous.completedAt + 1);
  assert.equal(match?.kind, "similar");
  assert.equal(match?.record, previous);
});

test("rememberExploration refreshes an existing key", () => {
  const records = new Map<string, ExploreCacheRecord>();
  const first = record();
  const second = record({ content: "new findings", completedAt: 20_000 });
  rememberExploration(records, first);
  rememberExploration(records, second);
  assert.equal(records.size, 1);
  assert.equal(records.get(first.key)?.content, "new findings");
});

test("rememberExploration bounds cache size", () => {
  const records = new Map<string, ExploreCacheRecord>();
  const oversized = record({
    key: "oversized",
    content: "x".repeat(MAX_EXPLORE_CACHE_BYTES + 1),
  });
  rememberExploration(records, oversized);
  assert.equal(records.size, 0);
});

test("restoreExploreCacheState rebuilds launched branch results without duplicate reuse entries", () => {
  const first = record({
    run: {
      ...record().run,
      runId: "run-original",
      tasks: [{ tokenCount: 100 }] as any,
    },
  });
  const fresh = record({
    key: "fresh-key",
    run: {
      ...record().run,
      runId: "run-fresh",
      tasks: [{ tokenCount: 50 }] as any,
    },
  });
  const entries = [
    {
      type: "message",
      message: {
        role: "toolResult",
        toolName: "explore",
        isError: false,
        content: [{ type: "text", text: first.content }],
        details: {
          cache: createExploreCacheMetadata(first, true),
          run: first.run,
          results: first.results,
        },
      },
    },
    {
      type: "message",
      message: {
        role: "toolResult",
        toolName: "explore",
        isError: false,
        content: [{ type: "text", text: `reuse prefix\n\n${first.content}` }],
        details: {
          cache: createExploreCacheMetadata(first, false),
          run: first.run,
          results: first.results,
        },
      },
    },
    {
      type: "custom",
      customType: EXPLORE_CACHE_ENTRY_TYPE,
      data: { record: fresh, launched: true },
    },
    {
      type: "custom",
      customType: WORKSPACE_GENERATION_ENTRY_TYPE,
      data: { generation: 3 },
    },
  ];

  const restored = restoreExploreCacheState(entries);
  assert.equal(restored.records.get(first.key)?.content, first.content);
  assert.equal(restored.records.get(fresh.key), fresh);
  assert.deepEqual(restored.runs.map((run) => run.runId), ["run-fresh", "run-original"]);
  assert.equal(restored.tokens, 150);
  assert.equal(restored.workspaceGeneration, 3);
});

test("active exploration subscribers cancel independently", async () => {
  let resolveRun: ((value: ExploreCacheRecord) => void) | undefined;
  const sharedController = new AbortController();
  const active: ActiveExploration = {
    key: "key",
    controller: sharedController,
    promise: new Promise((resolve) => {
      resolveRun = resolve;
    }),
    waiters: 0,
    settled: false,
  };
  const firstController = new AbortController();
  const secondController = new AbortController();
  const first = subscribeToActiveExploration(active, firstController.signal);
  const second = subscribeToActiveExploration(active, secondController.signal);

  firstController.abort(new Error("first stopped waiting"));
  await assert.rejects(first, /first stopped waiting/);
  assert.equal(sharedController.signal.aborted, false);
  assert.equal(active.waiters, 1);

  const completed = record();
  active.settled = true;
  resolveRun?.(completed);
  assert.equal(await second, completed);
  assert.equal(active.waiters, 0);
});

test("the final cancelled subscriber aborts shared exploration", async () => {
  const sharedController = new AbortController();
  const active: ActiveExploration = {
    key: "key",
    controller: sharedController,
    promise: new Promise(() => undefined),
    waiters: 0,
    settled: false,
  };
  const waiterController = new AbortController();
  const waiter = subscribeToActiveExploration(active, waiterController.signal);
  waiterController.abort(new Error("stop"));
  await assert.rejects(waiter, /stop/);
  assert.equal(sharedController.signal.aborted, true);
});

test("parseFreshExploreArgs accepts an optional intent", () => {
  assert.deepEqual(parseFreshExploreArgs("deep inspect caching"), { intent: "deep", task: "inspect caching" });
  assert.deepEqual(parseFreshExploreArgs("inspect caching"), { task: "inspect caching" });
  assert.deepEqual(parseFreshExploreArgs("  "), {});
});
