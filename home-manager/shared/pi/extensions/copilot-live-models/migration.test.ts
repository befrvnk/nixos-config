import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import assert from "node:assert/strict";
import test from "node:test";
import { fileURLToPath } from "node:url";

const migrationScript = fileURLToPath(new URL("./migrate-legacy-models-json.mjs", import.meta.url));

function runMigration(filePath: string): void {
  const result = spawnSync(process.execPath, [migrationScript, filePath], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
}

test("legacy models.json migration preserves unrelated configuration", async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), "pi-copilot-migration-"));
  const filePath = path.join(dir, "models.json");

  try {
    await writeFile(filePath, JSON.stringify({
      metadata: { keep: true },
      providers: {
        "github-copilot": { name: "GitHub Copilot (live catalog)", models: [] },
        other: { baseUrl: "https://example.test" },
      },
    }));

    runMigration(filePath);
    const migrated = JSON.parse(await readFile(filePath, "utf8"));
    assert.deepEqual(migrated.metadata, { keep: true });
    assert.deepEqual(migrated.providers, { other: { baseUrl: "https://example.test" } });
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test("legacy models.json migration removes an otherwise generated-only file", async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), "pi-copilot-migration-"));
  const filePath = path.join(dir, "models.json");

  try {
    await writeFile(filePath, JSON.stringify({
      providers: {
        "github-copilot": { name: "GitHub Copilot (live catalog)", models: [] },
      },
    }));

    runMigration(filePath);
    await assert.rejects(readFile(filePath), { code: "ENOENT" });
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
