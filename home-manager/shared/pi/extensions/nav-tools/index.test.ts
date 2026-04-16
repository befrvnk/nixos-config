import assert from "node:assert/strict";
import test from "node:test";
import navToolsExtension from "./index.ts";

test("nav-tools activates grep, find, and ls on each session start without duplicating entries", async () => {
  let activeTools = ["read", "bash", "grep"];
  let sessionStartHandler: (() => Promise<void>) | undefined;

  const pi = {
    getActiveTools() {
      return activeTools;
    },
    setActiveTools(nextTools: string[]) {
      activeTools = nextTools;
    },
    on(event: string, handler: () => Promise<void>) {
      if (event === "session_start") sessionStartHandler = handler;
    },
  } as any;

  navToolsExtension(pi);
  assert.ok(sessionStartHandler);

  await sessionStartHandler?.();
  assert.deepEqual(new Set(activeTools), new Set(["read", "bash", "grep", "find", "ls"]));

  const afterFirstStart = [...activeTools];
  await sessionStartHandler?.();
  assert.deepEqual(activeTools, afterFirstStart);
});
