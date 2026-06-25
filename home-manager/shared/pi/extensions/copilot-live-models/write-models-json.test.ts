import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, symlinkSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const extensionDir = path.dirname(fileURLToPath(import.meta.url));
const scriptPath = path.join(extensionDir, "write-models-json.ts");

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
