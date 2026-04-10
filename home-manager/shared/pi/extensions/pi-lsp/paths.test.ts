import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  detectLanguage,
  detectProjectRoot,
  ensureActionSupportsPath,
  resolveFilePath,
  stripAtPrefix,
  toTextDocumentIdentifier,
  toZeroIndexedPosition,
  walkParents,
} from "./paths.ts";

test("stripAtPrefix removes a leading @ once", () => {
  assert.equal(stripAtPrefix("@src/index.ts"), "src/index.ts");
  assert.equal(stripAtPrefix("src/index.ts"), "src/index.ts");
});

test("resolveFilePath resolves paths relative to cwd and strips @", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-paths-"));
  const file = path.join(dir, "src", "index.ts");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, "export const value = 1;\n");

  assert.equal(resolveFilePath("@src/index.ts", dir), fs.realpathSync.native(file));
  assert.throws(() => resolveFilePath("missing.ts", dir), /Path does not exist/);
});

test("detectLanguage prefers explicit override and otherwise uses file suffix", () => {
  assert.equal(detectLanguage("/tmp/example.ts"), "typescript");
  assert.equal(detectLanguage("/tmp/example.kt"), "kotlin");
  assert.equal(detectLanguage("/tmp/example.any", "java"), "java");
  assert.throws(() => detectLanguage("/tmp/example.txt"), /Unsupported language/);
});

test("detectProjectRoot walks up to language markers before .git fallback", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-root-"));
  const nested = path.join(root, "packages", "app", "src");
  const file = path.join(nested, "main.ts");
  fs.mkdirSync(nested, { recursive: true });
  fs.writeFileSync(path.join(root, "tsconfig.json"), "{}\n");
  fs.writeFileSync(file, "export {};\n");

  const realRoot = fs.realpathSync.native(root);
  assert.equal(detectProjectRoot(file, "typescript", nested), realRoot);

  fs.rmSync(path.join(root, "tsconfig.json"));
  fs.mkdirSync(path.join(root, ".git"));
  assert.equal(detectProjectRoot(file, "typescript", nested), realRoot);
  assert.deepEqual([...walkParents(nested)].slice(0, 3), [
    fs.realpathSync.native(nested),
    fs.realpathSync.native(path.join(root, "packages", "app")),
    fs.realpathSync.native(path.join(root, "packages")),
  ]);
});

test("toZeroIndexedPosition validates positive 1-indexed values", () => {
  assert.deepEqual(toZeroIndexedPosition(3, 7), { line: 2, character: 6 });
  assert.throws(() => toZeroIndexedPosition(0, 1), /positive 1-indexed/);
  assert.throws(() => toZeroIndexedPosition(1, undefined), /positive 1-indexed/);
});

test("toTextDocumentIdentifier and ensureActionSupportsPath produce document references", () => {
  const file = path.join(os.tmpdir(), "example.ts");
  assert.deepEqual(toTextDocumentIdentifier(file), {
    uri: pathToFileURL(file).href,
  });
  assert.equal(ensureActionSupportsPath("hover", file), file);
  assert.throws(() => ensureActionSupportsPath("hover", undefined), /requires a file path/);
});
