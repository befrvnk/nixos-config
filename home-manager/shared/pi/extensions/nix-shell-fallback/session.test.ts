import assert from "node:assert/strict";
import test from "node:test";
import { shouldRegisterBashTool } from "./session.ts";

test("shouldRegisterBashTool refreshes the wrapped bash tool when the session cwd changes", () => {
  assert.equal(shouldRegisterBashTool(undefined, "/repo/one"), true);
  assert.equal(shouldRegisterBashTool("/repo/one", "/repo/one"), false);
  assert.equal(shouldRegisterBashTool("/repo/one", "/repo/two"), true);
});
