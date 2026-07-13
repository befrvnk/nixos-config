import { promises as fs } from "node:fs";
import path from "node:path";

const REVIEW_GUIDELINES_FILE = "REVIEW_GUIDELINES.md";
const PI_DIRECTORY = ".pi";

async function realDirectory(targetPath: string): Promise<boolean> {
  try {
    return (await fs.lstat(targetPath)).isDirectory();
  } catch {
    return false;
  }
}

async function realFile(targetPath: string): Promise<boolean> {
  try {
    return (await fs.lstat(targetPath)).isFile();
  } catch {
    return false;
  }
}

function isWithin(root: string, candidate: string): boolean {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

export async function findProjectReviewGuidelinesPath(
  cwd: string,
  repositoryRoot?: string,
): Promise<string | undefined> {
  let currentDir = await fs.realpath(cwd);
  const stopRoot = repositoryRoot
    ? await fs.realpath(repositoryRoot)
    : path.parse(currentDir).root;
  if (!isWithin(stopRoot, currentDir)) currentDir = stopRoot;

  while (isWithin(stopRoot, currentDir)) {
    const piDir = path.join(currentDir, PI_DIRECTORY);
    if (await realDirectory(piDir)) {
      const guidelinesPath = path.join(currentDir, REVIEW_GUIDELINES_FILE);
      if (!(await realFile(guidelinesPath))) return undefined;
      const canonicalGuidelines = await fs.realpath(guidelinesPath);
      return isWithin(stopRoot, canonicalGuidelines) ? canonicalGuidelines : undefined;
    }

    if (currentDir === stopRoot) return undefined;
    const parentDir = path.dirname(currentDir);
    if (parentDir === currentDir) return undefined;
    currentDir = parentDir;
  }
  return undefined;
}

export async function loadProjectReviewGuidelines(
  cwd: string,
  repositoryRoot?: string,
): Promise<string | undefined> {
  const guidelinesPath = await findProjectReviewGuidelinesPath(cwd, repositoryRoot);
  if (!guidelinesPath) return undefined;

  try {
    const content = await fs.readFile(guidelinesPath, "utf8");
    const trimmed = content.trim();
    return trimmed || undefined;
  } catch {
    return undefined;
  }
}

export function composeAdditionalReviewInstructions(options: {
  extraPrompt?: string;
  projectGuidelines?: string;
}): string | undefined {
  const sections = [
    options.extraPrompt?.trim()
      ? ["User-provided focus:", options.extraPrompt.trim()].join("\n")
      : undefined,
    options.projectGuidelines?.trim()
      ? [
        "Project review guidelines (from REVIEW_GUIDELINES.md):",
        options.projectGuidelines.trim(),
      ].join("\n")
      : undefined,
  ].filter(Boolean);

  return sections.length > 0 ? sections.join("\n\n") : undefined;
}
