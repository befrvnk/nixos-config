import { promises as fs } from "node:fs";
import path from "node:path";

const REVIEW_GUIDELINES_FILE = "REVIEW_GUIDELINES.md";
const PI_DIRECTORY = ".pi";

async function directoryExists(targetPath: string): Promise<boolean> {
	try {
		const stats = await fs.stat(targetPath);
		return stats.isDirectory();
	} catch {
		return false;
	}
}

async function fileExists(targetPath: string): Promise<boolean> {
	try {
		const stats = await fs.stat(targetPath);
		return stats.isFile();
	} catch {
		return false;
	}
}

export async function findProjectReviewGuidelinesPath(
	cwd: string,
): Promise<string | undefined> {
	let currentDir = path.resolve(cwd);

	while (true) {
		const piDir = path.join(currentDir, PI_DIRECTORY);
		if (await directoryExists(piDir)) {
			const guidelinesPath = path.join(currentDir, REVIEW_GUIDELINES_FILE);
			return (await fileExists(guidelinesPath)) ? guidelinesPath : undefined;
		}

		const parentDir = path.dirname(currentDir);
		if (parentDir === currentDir) return undefined;
		currentDir = parentDir;
	}
}

export async function loadProjectReviewGuidelines(
	cwd: string,
): Promise<string | undefined> {
	const guidelinesPath = await findProjectReviewGuidelinesPath(cwd);
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
