import test from "node:test";
import assert from "node:assert/strict";
import {
  formatWarmupMessage,
  formatWorkspaceWarmupMessage,
  summarizeWarmupStatus,
} from "./warmup.ts";

test("summarizeWarmupStatus and formatWarmupMessage render actionable warmup details", () => {
  const summary = summarizeWarmupStatus({
    language: "kotlin",
    root: "/repo",
    pid: 4242,
    state: "initializing",
    startedAt: Date.now() - 1_500,
    initializedAt: undefined,
    readyAt: undefined,
    failedAt: undefined,
    openDocuments: 0,
    restartCount: 0,
    lastFailure: undefined,
    lastStderrLines: [],
    lastRequest: undefined,
  });

  const text = formatWarmupMessage("hover", summary);
  assert.match(text, /kotlin LSP is still warming up/i);
  assert.match(text, /Action: hover/);
  assert.match(text, /Root: \/repo/);
  assert.match(text, /State: initializing/);
  assert.match(text, /Suggestion: retry shortly or run \/lsp-status/);
});

test("formatWorkspaceWarmupMessage deduplicates warmup entries", () => {
  const text = formatWorkspaceWarmupMessage("workspace_symbols", [
    {
      language: "kotlin",
      root: "/repo",
      state: "starting",
      elapsedMs: 1_000,
    },
    {
      language: "kotlin",
      root: "/repo",
      state: "starting",
      elapsedMs: 1_500,
    },
    {
      language: "typescript",
      root: "/repo-web",
      state: "initializing",
      elapsedMs: 500,
    },
  ]);

  assert.match(text, /LSP results are still warming up for workspace_symbols/);
  assert.match(text, /- kotlin: starting/);
  assert.match(text, /- typescript: initializing/);
  assert.equal((text.match(/- kotlin:/g) ?? []).length, 1);
});
