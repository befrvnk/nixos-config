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

function findHighestMatchingRoot(directories: string[], markers: string[]): string | undefined {
  let match: string | undefined;

  for (const dir of directories) {
    if (markers.some((marker) => fs.existsSync(path.join(dir, marker)))) {
      match = dir;
    }
  }

  return match;
}

function detectKotlinProjectRoot(startDir: string): string | undefined {
  const directories = [...walkParents(startDir)];

  const gradleWorkspaceRoot = findHighestMatchingRoot(directories, [
    "settings.gradle.kts",
    "settings.gradle",
    "gradlew",
  ]);
  if (gradleWorkspaceRoot) return gradleWorkspaceRoot;

  const mavenRoot = findHighestMatchingRoot(directories, ["pom.xml"]);
  if (mavenRoot) return mavenRoot;

  const gradleModuleRoot = findHighestMatchingRoot(directories, ["build.gradle.kts", "build.gradle"]);
  if (gradleModuleRoot) return gradleModuleRoot;

  return undefined;
}

export function detectProjectRoot(filePath: string, language: SupportedLanguage, _cwd: string): string {
  const startDir = fs.realpathSync.native(fs.statSync(filePath).isDirectory() ? filePath : path.dirname(filePath));

  if (language === "kotlin") {
    const kotlinRoot = detectKotlinProjectRoot(startDir);
    if (!kotlinRoot) {
      throw new Error(
        `Kotlin LSP only works in Gradle or Maven projects. No Kotlin project markers were found near: ${filePath}`,
      );
    }
    return kotlinRoot;
  }

  const markers = ROOT_MARKERS[language];

  for (const dir of walkParents(startDir)) {
    if (markers.some((marker) => fs.existsSync(path.join(dir, marker)))) return dir;
  }

  for (const dir of walkParents(startDir)) {
    if (fs.existsSync(path.join(dir, ".git"))) return dir;
  }

  return startDir;
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
  if (!Number.isInteger(line) || !Number.isInteger(character) || line < 1 || character < 1) {
    throw new Error("This action requires both line and character as positive 1-indexed integers.");
  }

  return {
    line: line - 1,
    character: character - 1,
  };
}

export function toTextDocumentIdentifier(filePath: string): { uri: string } {
  return { uri: pathToFileURL(filePath).href };
}

export function ensureActionSupportsPath(action: QueryAction, filePath: string | undefined): string {
  if (!filePath) throw new Error(`Action ${action} requires a file path.`);
  return filePath;
}
