import assert from "node:assert/strict";
import fs from "node:fs/promises";
import test from "node:test";
import { LazyOutputLog } from "./output-log.ts";

test("LazyOutputLog creates private exclusive spill files", async () => {
  const log = new LazyOutputLog(1);
  await log.append("complete output\n");
  const outputPath = await log.finish();
  assert.ok(outputPath);

  try {
    assert.equal(await fs.readFile(outputPath, "utf8"), "complete output\n");
    if (process.platform !== "win32") {
      assert.equal((await fs.stat(outputPath)).mode & 0o777, 0o600);
    }
  } finally {
    await fs.rm(outputPath, { force: true });
  }
});

test("LazyOutputLog serializes concurrent appends", async () => {
  const log = new LazyOutputLog(0);
  await Promise.all([
    log.append("one\n"),
    log.append("two\n"),
    log.append("three\n"),
  ]);
  const outputPath = await log.finish();
  assert.ok(outputPath);

  try {
    assert.equal(await fs.readFile(outputPath, "utf8"), "one\ntwo\nthree\n");
  } finally {
    await fs.rm(outputPath, { force: true });
  }
});
