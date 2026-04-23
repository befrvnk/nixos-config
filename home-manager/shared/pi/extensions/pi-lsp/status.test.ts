import test from "node:test";
import assert from "node:assert/strict";
import { formatLogDetails, formatStatusDetails } from "./status.ts";

test("formatStatusDetails renders empty and active runtime states", () => {
  const empty = formatStatusDetails({
    statuses: [],
    configuredLanguages: ["kotlin", "typescript"],
    configPath: "/tmp/pi-lsp.json",
  });

  assert.match(empty, /No tracked language server runtimes/);
  assert.match(empty, /Configured languages: kotlin, typescript/);

  const text = formatStatusDetails({
    statuses: [
      {
        language: "kotlin",
        root: "/repo",
        pid: 4242,
        state: "failed",
        startedAt: Date.now() - 5_000,
        initializedAt: undefined,
        readyAt: undefined,
        failedAt: Date.now() - 2_000,
        openDocuments: 1,
        restartCount: 2,
        lastFailure: {
          category: "initialize_timeout",
          message: "Timed out waiting for initialize from kotlin",
          at: Date.now() - 2_000,
          method: "initialize",
        },
        lastStderrLines: ["Gradle import still running"],
        lastRequest: {
          method: "initialize",
          startedAt: Date.now() - 3_000,
          completedAt: Date.now() - 2_000,
          durationMs: 1_000,
          ok: false,
          error: "Timed out waiting for initialize from kotlin",
        },
      },
    ],
    configuredLanguages: ["kotlin"],
    configPath: "/tmp/pi-lsp.json",
  });

  assert.match(text, /Language server runtimes \(1\)/);
  assert.match(text, /kotlin — failed pid 4242/);
  assert.match(text, /root: \/repo/);
  assert.match(text, /restarts: 2/);
  assert.match(text, /last request: initialize error: Timed out waiting for initialize from kotlin in 1000ms/);
  assert.match(text, /last failure: initialize_timeout \(initialize\): Timed out waiting for initialize from kotlin/);
  assert.match(text, /recent stderr:/);
  assert.match(text, /Gradle import still running/);
});

test("formatStatusDetails renders explicit workspace conflict hints", () => {
  const text = formatStatusDetails({
    statuses: [
      {
        language: "kotlin",
        root: "/repo",
        pid: undefined,
        state: "failed",
        startedAt: Date.now() - 8_000,
        initializedAt: undefined,
        readyAt: undefined,
        failedAt: Date.now() - 3_000,
        openDocuments: 0,
        restartCount: 0,
        lastFailure: {
          category: "workspace_session_conflict",
          message:
            "Another kotlin-lsp session is already attached to this workspace. Workspace: /repo. Competing PID(s): 5151.",
          at: Date.now() - 3_000,
          method: "initialize",
        },
        lastStderrLines: [],
        lastRequest: undefined,
      },
    ],
    configuredLanguages: ["kotlin"],
    configPath: "/tmp/pi-lsp.json",
  });

  assert.match(text, /last failure: workspace_session_conflict \(initialize\): Another kotlin-lsp session is already attached to this workspace/);
  assert.match(text, /conflict hint: kotlin-lsp allows only one client per workspace root/);
  assert.match(text, /stop the other pi\/editor session using this workspace root/);
  assert.match(text, /kill the competing kotlin-lsp PID\(s\) mentioned above/);
  assert.match(text, /use a separate worktree if you need parallel Kotlin sessions/);
});

test("formatLogDetails renders recent lifecycle log lines", () => {
  const text = formatLogDetails({
    statuses: [
      {
        language: "kotlin",
        root: "/repo",
        pid: 4242,
        state: "indexing",
        startedAt: Date.now() - 5_000,
        initializedAt: Date.now() - 4_000,
        readyAt: undefined,
        failedAt: undefined,
        openDocuments: 0,
        restartCount: 1,
        lastFailure: undefined,
        lastStderrLines: ["Gradle import running"],
        lastRequest: undefined,
      },
    ],
    logs: [
      "2026-01-01T00:00:00.000Z [lifecycle] stopped -> starting",
      "2026-01-01T00:00:01.000Z [stderr] Gradle import running",
    ],
    configPath: "/tmp/pi-lsp.json",
  });

  assert.match(text, /LSP log view/);
  assert.match(text, /Tracked runtimes: 1/);
  assert.match(text, /kotlin — indexing — \/repo/);
  assert.match(text, /Recent lifecycle, progress, request, and stderr lines:/);
  assert.match(text, /\[lifecycle\] stopped -> starting/);
  assert.match(text, /\[stderr\] Gradle import running/);
});

test("formatLogDetails renders explicit workspace conflict hints", () => {
  const text = formatLogDetails({
    statuses: [
      {
        language: "kotlin",
        root: "/repo",
        pid: undefined,
        state: "failed",
        startedAt: Date.now() - 5_000,
        initializedAt: undefined,
        readyAt: undefined,
        failedAt: Date.now() - 2_000,
        openDocuments: 0,
        restartCount: 0,
        lastFailure: {
          category: "workspace_session_conflict",
          message:
            "Another kotlin-lsp session is already attached to this workspace. Workspace: /repo. Competing PID(s): 5151.",
          at: Date.now() - 2_000,
          method: "initialize",
        },
        lastStderrLines: [],
        lastRequest: undefined,
      },
    ],
    logs: [
      "2026-01-01T00:00:00.000Z [failure] workspace_session_conflict: Another kotlin-lsp session is already attached to this workspace.",
    ],
    configPath: "/tmp/pi-lsp.json",
  });

  assert.match(text, /Workspace conflict hints:/);
  assert.match(text, /- kotlin — \/repo/);
  assert.match(text, /kotlin-lsp allows only one client per workspace root/);
  assert.match(text, /stop the other pi\/editor session for this root or kill stale competing kotlin-lsp processes/);
  assert.match(text, /use a separate worktree if you need parallel Kotlin sessions/);
  assert.match(text, /workspace_session_conflict/);
});
