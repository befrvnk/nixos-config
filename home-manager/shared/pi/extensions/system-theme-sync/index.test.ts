import test from "node:test";
import assert from "node:assert/strict";
import { applyTheme, createSerializedPoller, parseLinuxTheme, syncThemeSafely } from "./index.ts";

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

test("createSerializedPoller waits for each task before scheduling the next", async () => {
  let resolveTask: (() => void) | undefined;
  let active = 0;
  let maximumActive = 0;
  const scheduled: Array<() => void> = [];
  const cancelled: unknown[] = [];
  const poller = createSerializedPoller(
    async () => {
      active += 1;
      maximumActive = Math.max(maximumActive, active);
      await new Promise<void>((resolve) => {
        resolveTask = resolve;
      });
      active -= 1;
    },
    2_000,
    {
      schedule: (callback) => {
        scheduled.push(callback);
        return callback;
      },
      cancel: (handle) => cancelled.push(handle),
    },
  );

  const initial = poller.start();
  await Promise.resolve();
  assert.equal(scheduled.length, 0);
  resolveTask?.();
  await initial;
  assert.equal(scheduled.length, 1);

  scheduled.shift()?.();
  await Promise.resolve();
  assert.equal(scheduled.length, 0);
  resolveTask?.();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(scheduled.length, 1);
  assert.equal(maximumActive, 1);

  poller.stop();
  assert.equal(cancelled.length, 1);
});

test("createSerializedPoller does not reschedule an in-flight task after stop", async () => {
  let resolveTask: (() => void) | undefined;
  const scheduled: Array<() => void> = [];
  const poller = createSerializedPoller(
    () => new Promise<void>((resolve) => {
      resolveTask = resolve;
    }),
    2_000,
    { schedule: (callback) => scheduled.push(callback) - 1 },
  );

  const started = poller.start();
  await Promise.resolve();
  poller.stop();
  resolveTask?.();
  await started;
  assert.deepEqual(scheduled, []);
});

test("syncThemeSafely ignores stale results and errors", async () => {
  let current = true;
  const notifications: string[] = [];
  const calls: string[] = [];
  const ctx = {
    ui: {
      setTheme(theme: string) {
        calls.push(theme);
        return { success: true };
      },
    },
  } as any;

  assert.equal(
    await syncThemeSafely(ctx, {
      currentTheme: "light",
      detect: async () => {
        current = false;
        return "dark";
      },
      shouldApply: () => current,
      notifyError: (message) => notifications.push(message),
    }),
    "light",
  );
  assert.deepEqual(calls, []);
  assert.deepEqual(notifications, []);
});

test("syncThemeSafely swallows detector and theme-apply failures", async () => {
  const notifications: string[] = [];
  const ctx = {
    ui: {
      setTheme() {
        return { success: false, error: "theme missing" };
      },
    },
  } as any;

  assert.equal(
    await syncThemeSafely(ctx, {
      currentTheme: "light",
      detect: async () => {
        throw new Error("detector offline");
      },
      notifyError: (message) => notifications.push(message),
    }),
    "light",
  );
  assert.equal(
    await syncThemeSafely(ctx, {
      currentTheme: "light",
      detect: async () => "dark",
      notifyError: (message) => notifications.push(message),
    }),
    "light",
  );

  assert.deepEqual(notifications, ["detector offline", "theme missing"]);
});
