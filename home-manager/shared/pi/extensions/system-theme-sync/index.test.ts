import test from "node:test";
import assert from "node:assert/strict";
import { applyTheme, parseLinuxTheme } from "./index.ts";

test("parseLinuxTheme recognizes dark, light, and default outputs", () => {
  assert.equal(parseLinuxTheme("'prefer-dark'"), "dark");
  assert.equal(parseLinuxTheme("PREFER-LIGHT"), "light");
  assert.equal(parseLinuxTheme("default"), "light");
  assert.equal(parseLinuxTheme("  "), undefined);
  assert.equal(parseLinuxTheme("unknown"), undefined);
});

test("applyTheme forwards the mapped theme name and returns the selected mode", () => {
  const calls: string[] = [];
  const ctx = {
    ui: {
      setTheme(theme: string) {
        calls.push(theme);
        return { success: true };
      },
    },
  } as any;

  assert.equal(applyTheme(ctx, "dark"), "dark");
  assert.deepEqual(calls, ["dark"]);
});

test("applyTheme throws when ui.setTheme reports a failure", () => {
  const ctx = {
    ui: {
      setTheme() {
        return { success: false, error: "not available" };
      },
    },
  } as any;

  assert.throws(() => applyTheme(ctx, "light"), /not available/);
});
