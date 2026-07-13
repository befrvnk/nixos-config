import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { canonicalizeRoot, resolvePathWithinRoot } from "./path-security.ts";

test("resolvePathWithinRoot rejects lexical and symlink escapes", () => {
  const parent = fs.mkdtempSync(path.join(os.tmpdir(), "pi-path-security-"));
  const root = path.join(parent, "repo");
  const outside = path.join(parent, "secret.txt");
  fs.mkdirSync(path.join(root, "src"), { recursive: true });
  fs.writeFileSync(path.join(root, "src", "file.ts"), "safe");
  fs.writeFileSync(outside, "secret");
  fs.symlinkSync(outside, path.join(root, "outside-link"));
  fs.symlinkSync(parent, path.join(root, "outside-dir"));
  fs.symlinkSync(path.join(root, "src", "file.ts"), path.join(root, "inside-link"));

  try {
    const canonicalRoot = canonicalizeRoot(root);
    assert.equal(resolvePathWithinRoot(root, "src/file.ts"), path.join(canonicalRoot, "src", "file.ts"));
    assert.equal(resolvePathWithinRoot(root, "@src/missing.ts"), path.join(canonicalRoot, "src", "missing.ts"));
    assert.equal(resolvePathWithinRoot(root, "../secret.txt"), undefined);
    assert.equal(resolvePathWithinRoot(root, outside), undefined);
    assert.equal(resolvePathWithinRoot(root, "outside-link"), undefined);
    assert.equal(resolvePathWithinRoot(root, "outside-dir/secret.txt"), undefined);
    assert.equal(resolvePathWithinRoot(root, "inside-link"), path.join(canonicalRoot, "src", "file.ts"));
  } finally {
    fs.rmSync(parent, { recursive: true, force: true });
  }
});
