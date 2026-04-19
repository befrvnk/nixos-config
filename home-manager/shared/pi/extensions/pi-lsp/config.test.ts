import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

async function importWithConfigPath<T>(
  modulePath: string,
  configPath: string,
): Promise<T> {
  const previous = process.env.PI_LSP_CONFIG;
  process.env.PI_LSP_CONFIG = configPath;
  try {
    return (await import(`${modulePath}?test=${Date.now()}-${Math.random()}`)) as T;
  } finally {
    if (previous === undefined) delete process.env.PI_LSP_CONFIG;
    else process.env.PI_LSP_CONFIG = previous;
  }
}

test("tryLoadConfig reports invalid configuration files without throwing", async () => {
  const configPath = path.join(os.tmpdir(), `pi-lsp-invalid-${Date.now()}.json`);
  fs.writeFileSync(configPath, JSON.stringify({ nope: true }));

  const { tryLoadConfig } = await importWithConfigPath<typeof import("./config.ts")>(
    "./config.ts",
    configPath,
  );

  assert.match(tryLoadConfig().error ?? "", /Invalid pi-lsp config/);
});

test("formatStatusDetails reports missing config files gracefully", async () => {
  const configPath = path.join(os.tmpdir(), `pi-lsp-missing-${Date.now()}.json`);
  const { formatStatusDetails } = await import("./status.ts");
  const details = formatStatusDetails({
    statuses: [],
    configuredLanguages: [],
    configPath,
    configError: `Missing pi-lsp config: ${configPath}`,
  });

  assert.match(details, /No tracked language server runtimes/);
  assert.match(details, /Configured languages: none/);
  assert.match(details, /Config status: Missing pi-lsp config/);
});
