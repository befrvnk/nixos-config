import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { LANGUAGE_EXTENSIONS, ROOT_MARKERS } from "./constants.js";
import type { Position, QueryAction, SupportedLanguage } from "./types.js";

export function stripAtPrefix(value: string): string {
  return value.startsWith("@") ? value.slice(1) : value;
}

export function resolveFilePath(rawPath: string, cwd: string): string {
  const resolved = path.resolve(cwd, stripAtPrefix(rawPath));
  if (!fs.existsSync(resolved)) throw new Error(`Path does not exist: ${rawPath}`);
  return fs.realpathSync.native(resolved);
}

export function detectLanguage(filePath: string, explicit?: SupportedLanguage): SupportedLanguage {
  if (explicit) return explicit;

  const lowerPath = filePath.toLowerCase();
  const match = LANGUAGE_EXTENSIONS.find((entry) => entry.suffixes.some((suffix) => lowerPath.endsWith(suffix)));
  if (!match) throw new Error(`Unsupported language for path: ${filePath}`);
  return match.language;
}

export function detectProjectRoot(filePath: string, language: SupportedLanguage, cwd: string): string {
  const startDir = fs.statSync(filePath).isDirectory() ? filePath : path.dirname(filePath);
  const markers = ROOT_MARKERS[language];

  for (const dir of walkParents(startDir)) {
    if (markers.some((marker) => fs.existsSync(path.join(dir, marker)))) return dir;
  }

  for (const dir of walkParents(startDir)) {
    if (fs.existsSync(path.join(dir, ".git"))) return dir;
  }

  return fs.existsSync(cwd) ? fs.realpathSync.native(cwd) : startDir;
}

export function* walkParents(startDir: string): Generator<string> {
  let current = fs.realpathSync.native(startDir);
  while (true) {
    yield current;
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
}

export function toZeroIndexedPosition(line: number | undefined, character: number | undefined): Position {
  if (!line || !character) {
    throw new Error("This action requires both line and character (1-indexed).");
  }

  return {
    line: Math.max(0, line - 1),
    character: Math.max(0, character - 1),
  };
}

export function toTextDocumentIdentifier(filePath: string): { uri: string } {
  return { uri: pathToFileURL(filePath).href };
}

export function ensureActionSupportsPath(action: QueryAction, filePath: string | undefined): string {
  if (!filePath) throw new Error(`Action ${action} requires a file path.`);
  return filePath;
}
