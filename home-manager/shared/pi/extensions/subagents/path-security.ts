import fs from "node:fs";
import path from "node:path";
import { stripAtPrefix } from "./guard-utils.ts";

export function canonicalizeRoot(root: string): string {
  return fs.realpathSync.native(path.resolve(root));
}

export function isPathWithinRoot(root: string, candidate: string): boolean {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

export function resolveLexicalPathWithinRoot(root: string, input: string): string | undefined {
  const canonicalRoot = canonicalizeRoot(root);
  const value = stripAtPrefix(input.trim());
  if (!value) return undefined;
  const candidate = path.resolve(canonicalRoot, value);
  return isPathWithinRoot(canonicalRoot, candidate) ? candidate : undefined;
}

export function resolvePathWithinRoot(root: string, input: string): string | undefined {
  const canonicalRoot = canonicalizeRoot(root);
  const candidate = resolveLexicalPathWithinRoot(canonicalRoot, input);
  if (!candidate) return undefined;

  let existing = candidate;
  const suffix: string[] = [];
  while (!fs.existsSync(existing)) {
    const parent = path.dirname(existing);
    if (parent === existing) return undefined;
    suffix.unshift(path.basename(existing));
    existing = parent;
  }

  const canonicalExisting = fs.realpathSync.native(existing);
  if (!isPathWithinRoot(canonicalRoot, canonicalExisting)) return undefined;
  const resolved = path.join(canonicalExisting, ...suffix);
  return isPathWithinRoot(canonicalRoot, resolved) ? resolved : undefined;
}
