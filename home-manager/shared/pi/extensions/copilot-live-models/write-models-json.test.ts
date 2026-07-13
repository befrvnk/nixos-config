import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, symlinkSync } from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { atomicWriteTextFile } from "./write-models-json.ts";

const extensionDir = path.dirname(fileURLToPath(import.meta.url));
const scriptPath = path.join(extensionDir, "write-models-json.ts");

test("atomicWriteTextFile replaces complete content with private permissions", async () => {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "pi-copilot-atomic-"));
  const destination = path.join(tmpDir, "models.json");

  try {
    await fs.writeFile(destination, "old complete content", "utf8");
    await atomicWriteTextFile(destination, "new complete content\n");

    assert.equal(await fs.readFile(destination, "utf8"), "new complete content\n");
    if (process.platform !== "win32") {
      assert.equal((await fs.stat(destination)).mode & 0o777, 0o600);
    }
    assert.deepEqual(await fs.readdir(tmpDir), ["models.json"]);
  } finally {
    await fs.rm(tmpDir, { recursive: true, force: true });
  }
});

test("atomicWriteTextFile preserves the destination and cleans up after rename failure", async () => {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), "pi-copilot-atomic-"));
  const destination = path.join(tmpDir, "models.json");
  await fs.writeFile(destination, "old complete content", "utf8");

  try {
    await assert.rejects(
      atomicWriteTextFile(destination, "new content", {
        rename: async () => {
          throw new Error("forced rename failure");
        },
      }),
      /forced rename failure/,
    );

    assert.equal(await fs.readFile(destination, "utf8"), "old complete content");
    assert.deepEqual(await fs.readdir(tmpDir), ["models.json"]);
  } finally {
    await fs.rm(tmpDir, { recursive: true, force: true });
  }
});

test("write-models-json runs when invoked through a Home Manager-style symlink", () => {
  const tmpDir = mkdtempSync(path.join(os.tmpdir(), "pi-copilot-live-models-"));

  try {
    const linkedScriptPath = path.join(tmpDir, "write-models-json.ts");
    symlinkSync(scriptPath, linkedScriptPath);

    const result = spawnSync(process.execPath, ["--experimental-strip-types", linkedScriptPath], {
      encoding: "utf8",
      env: {
        ...process.env,
        PI_CODING_AGENT_DIR: path.join(tmpDir, "agent"),
        PI_COPILOT_LIVE_MODELS: "1",
        PI_COPILOT_LIVE_MODELS_DEBUG: "1",
      },
    });

    // With an empty temporary agent dir, a running writer fails open with exit 2.
    // The symlink regression exited 0 because the main-module guard never ran.
    assert.equal(result.status, 2, result.stderr || result.stdout);
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }
});
