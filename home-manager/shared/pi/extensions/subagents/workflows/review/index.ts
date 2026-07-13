import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	parseBullets,
	shortenPath,
	shortTaskId,
	uniqueNonEmptyStrings,
} from "../../formatting.js";
import { DEFAULT_REVIEWERS } from "./config.js";
import { buildReviewConsensus } from "./consensus.js";
import {
	composeAdditionalReviewInstructions,
	loadProjectReviewGuidelines,
} from "./guidelines.js";
import { FAST_EXPLORE_MODEL } from "../../model-policy.js";
import type { ReviewerConfig } from "../../model-policy.js";
import type {
	ParsedOutputMeta,
	ParsedSubagentOutput,
	SubagentTaskInput,
	SubagentTaskResult,
} from "../../types.js";

const MAX_DIFF_CHARS = 60_000;
const MAX_CONTEXT_PACKET_CHARS = 80_000;
const MAX_CONTEXT_FILE_CHARS = 20_000;
const MAX_UNTRACKED_PREVIEW_BYTES = 16_000;
const MAX_UNTRACKED_PREVIEW_LINES = 160;
const EMPTY_TREE_HASH = "4b825dc642cb6eb9a060e54bf8d69288fbee4904";

export type ReviewTarget =
	| { type: "uncommitted" }
	| { type: "staged" }
	| { type: "baseBranch"; branch: string }
	| { type: "commit"; sha: string };

export type ReviewRequest = {
	prompt?: string;
	cwd?: string;
};

export type ReviewCommandRequest = ReviewRequest & {
	target: ReviewTarget;
};

export type ReviewContext = {
	repoRoot: string;
	inspectionRoot: string;
	inspectionRootDescription: string;
	target: string;
	baseRef: string;
	statusShort: string;
	diffStat: string;
	changedFiles: string[];
	diffPreview: string;
	diffWasTruncated: boolean;
	repositoryContextPacket: string;
	repositoryContextWasTruncated: boolean;
	inspectionWarnings: string[];
	changeBrief?: string;
	changeBriefWarnings?: string[];
};

type GitCommandResult = {
	stdout: string;
	stderr: string;
	code: number;
};

type ResolvedBaseRef = {
	displayBaseRef: string;
	diffBaseRef: string;
};

type DiffMode = "working-tree" | "staged";

type DiffReviewContextOptions = {
	targetLabel: string;
	diffMode: DiffMode;
	diffBaseRef: string;
	displayBaseRef: string;
	includeRepositoryContext?: boolean;
};

type InspectionSnapshot = {
	root: string;
	description: string;
	warnings?: string[];
	cleanup?: () => Promise<void>;
};

async function runGit(
	pi: ExtensionAPI,
	cwd: string,
	args: string[],
	signal?: AbortSignal,
): Promise<GitCommandResult> {
	const result = await pi.exec("git", args, { cwd, signal } as {
		cwd: string;
		signal?: AbortSignal;
	});
	return {
		stdout: result.stdout ?? "",
		stderr: result.stderr ?? "",
		code: result.code ?? 1,
	};
}

function removeDirectoryQuietly(directory: string): void {
	try {
		fs.rmSync(directory, { recursive: true, force: true });
	} catch {
		// best-effort cleanup only
	}
}

async function cleanupQuietly(cleanup: (() => Promise<void>) | undefined): Promise<void> {
	try {
		await cleanup?.();
	} catch {
		// best-effort cleanup only
	}
}

function createTempReviewDirectory(prefix: string): string {
	return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

function ensureTrailingPathSeparator(directory: string): string {
	return directory.endsWith(path.sep) ? directory : `${directory}${path.sep}`;
}

async function createStagedInspectionSnapshot(
	pi: ExtensionAPI,
	repoRoot: string,
	signal?: AbortSignal,
): Promise<InspectionSnapshot> {
	const tempRoot = createTempReviewDirectory("pi-review-staged-");
	const snapshotRoot = path.join(tempRoot, "index");
	fs.mkdirSync(snapshotRoot, { recursive: true });

	const result = await runGit(
		pi,
		repoRoot,
		[
			"checkout-index",
			"--force",
			"--all",
			`--prefix=${ensureTrailingPathSeparator(snapshotRoot)}`,
		],
		signal,
	);
	if (result.code !== 0) {
		removeDirectoryQuietly(tempRoot);
		throw new Error(
			result.stderr.trim() ||
				result.stdout.trim() ||
				"Failed to create staged index snapshot for review inspection.",
		);
	}

	return {
		root: snapshotRoot,
		description: "temporary staged-index snapshot",
		warnings: [
			"This review inspects a staged-index snapshot. File reads reflect staged content; git commands may not be available inside the snapshot.",
		],
		cleanup: async () => removeDirectoryQuietly(tempRoot),
	};
}

async function createCommitInspectionSnapshot(
	pi: ExtensionAPI,
	repoRoot: string,
	sha: string,
	signal?: AbortSignal,
): Promise<InspectionSnapshot> {
	const tempRoot = createTempReviewDirectory("pi-review-commit-");
	const cloneRoot = path.join(tempRoot, "repo");
	const cloneResult = await runGit(
		pi,
		tempRoot,
		["clone", "--quiet", "--shared", "--no-checkout", repoRoot, cloneRoot],
		signal,
	);
	if (cloneResult.code !== 0) {
		removeDirectoryQuietly(tempRoot);
		throw new Error(
			cloneResult.stderr.trim() ||
				cloneResult.stdout.trim() ||
				`Failed to create temporary clone for review inspection: ${sha}`,
		);
	}

	const checkoutResult = await runGit(
		pi,
		cloneRoot,
		["checkout", "--quiet", "--detach", sha],
		signal,
	);
	if (checkoutResult.code !== 0) {
		removeDirectoryQuietly(tempRoot);
		throw new Error(
			checkoutResult.stderr.trim() ||
				checkoutResult.stdout.trim() ||
				`Failed to checkout commit snapshot for review inspection: ${sha}`,
		);
	}

	return {
		root: cloneRoot,
		description: `temporary detached clone at ${sha.slice(0, 12)}`,
		cleanup: async () => removeDirectoryQuietly(tempRoot),
	};
}

async function resolveRepoRoot(
	pi: ExtensionAPI,
	cwd: string,
	signal?: AbortSignal,
): Promise<string> {
	const repoResult = await runGit(
		pi,
		cwd,
		["rev-parse", "--show-toplevel"],
		signal,
	);
	if (repoResult.code !== 0) {
		throw new Error(
			`Not inside a git repository: ${repoResult.stderr.trim() || repoResult.stdout.trim() || cwd}`,
		);
	}
	return repoResult.stdout.trim();
}

async function resolveBaseRef(
	pi: ExtensionAPI,
	repoRoot: string,
	baseRef: string,
	signal?: AbortSignal,
): Promise<ResolvedBaseRef> {
	const result = await runGit(
		pi,
		repoRoot,
		["rev-parse", "--verify", "--quiet", `${baseRef}^{commit}`],
		signal,
	);
	if (result.code === 0) {
		return {
			diffBaseRef: baseRef,
			displayBaseRef: baseRef,
		};
	}

	if (baseRef === "HEAD") {
		return {
			diffBaseRef: EMPTY_TREE_HASH,
			displayBaseRef: "HEAD (unborn; empty tree)",
		};
	}

	throw new Error(`Invalid or unknown baseRef: ${baseRef}`);
}

async function resolveMergeBase(
	pi: ExtensionAPI,
	repoRoot: string,
	branch: string,
	signal?: AbortSignal,
): Promise<ResolvedBaseRef> {
	const trimmedBranch = branch.trim();
	if (!trimmedBranch) throw new Error("Branch name is required.");

	const branchResult = await runGit(
		pi,
		repoRoot,
		["rev-parse", "--verify", "--quiet", `${trimmedBranch}^{commit}`],
		signal,
	);
	if (branchResult.code !== 0) {
		throw new Error(`Invalid or unknown branch: ${trimmedBranch}`);
	}

	const mergeBaseResult = await runGit(
		pi,
		repoRoot,
		["merge-base", "HEAD", trimmedBranch],
		signal,
	);
	if (mergeBaseResult.code !== 0) {
		const headResult = await runGit(
			pi,
			repoRoot,
			["rev-parse", "--verify", "--quiet", "HEAD^{commit}"],
			signal,
		);
		if (headResult.code !== 0) {
			throw new Error(
				"Base-branch review requires the current branch to have at least one commit.",
			);
		}
		throw new Error(
			`Unable to determine merge base with branch: ${trimmedBranch}`,
		);
	}

	const mergeBaseSha = mergeBaseResult.stdout.trim();
	if (!mergeBaseSha) {
		throw new Error(
			`Unable to determine merge base with branch: ${trimmedBranch}`,
		);
	}

	return {
		diffBaseRef: mergeBaseSha,
		displayBaseRef: `${trimmedBranch} (merge base ${mergeBaseSha.slice(0, 12)})`,
	};
}

function formatUntrackedDiffStat(untrackedFiles: string[]): string | undefined {
	if (untrackedFiles.length === 0) return undefined;
	return [
		"Untracked files:",
		...untrackedFiles.map((file) => `- ${file} (untracked)`),
	].join("\n");
}

function readUntrackedPreview(absolutePath: string): {
	sample: Buffer;
	truncated: boolean;
} {
	const fd = fs.openSync(absolutePath, "r");
	try {
		const sample = Buffer.alloc(MAX_UNTRACKED_PREVIEW_BYTES + 1);
		const bytesRead = fs.readSync(fd, sample, 0, sample.length, 0);
		return {
			sample: sample.subarray(0, bytesRead),
			truncated: bytesRead > MAX_UNTRACKED_PREVIEW_BYTES,
		};
	} finally {
		fs.closeSync(fd);
	}
}

function buildUntrackedFilePreview(repoRoot: string, file: string): string {
	const absolutePath = path.join(repoRoot, file);

	try {
		const { sample, truncated: truncatedByBytes } =
			readUntrackedPreview(absolutePath);
		const previewSample = sample.subarray(0, MAX_UNTRACKED_PREVIEW_BYTES);
		if (previewSample.includes(0)) {
			return [
				`diff --git a/${file} b/${file}`,
				"new file mode 100644",
				"--- /dev/null",
				`+++ b/${file}`,
				"Binary file preview omitted for untracked file.",
			].join("\n");
		}

		const previewText = previewSample.toString("utf8").replace(/\r\n/g, "\n");
		const allPreviewLines = previewText.split("\n");
		const previewLines = allPreviewLines.slice(0, MAX_UNTRACKED_PREVIEW_LINES);
		const truncated =
			truncatedByBytes || allPreviewLines.length > MAX_UNTRACKED_PREVIEW_LINES;

		const bodyLines = previewLines.map((line) => `+${line}`);
		if (truncated) bodyLines.push("+[... truncated]");

		return [
			`diff --git a/${file} b/${file}`,
			"new file mode 100644",
			"--- /dev/null",
			`+++ b/${file}`,
			`@@ -0,0 +1,${Math.max(previewLines.length, 1)} @@`,
			...bodyLines,
		].join("\n");
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		return [
			`diff --git a/${file} b/${file}`,
			"new file mode 100644",
			"--- /dev/null",
			`+++ b/${file}`,
			`Unable to read untracked file preview: ${message}`,
		].join("\n");
	}
}

function buildUntrackedDiffPreview(
	repoRoot: string,
	untrackedFiles: string[],
): string | undefined {
	if (untrackedFiles.length === 0) return undefined;
	return untrackedFiles
		.map((file) => buildUntrackedFilePreview(repoRoot, file))
		.join("\n\n");
}

function buildCombinedDiffPreview(
	repoRoot: string,
	diffText: string,
	untrackedFiles: string[],
): string {
	const sections = [
		diffText.trim(),
		buildUntrackedDiffPreview(repoRoot, untrackedFiles),
	]
		.map((section) => section?.trim())
		.filter(Boolean);
	return sections.join("\n\n");
}

function resolvePathUnderRoot(root: string, file: string): string | undefined {
	const resolvedRoot = path.resolve(root);
	const resolvedPath = path.resolve(resolvedRoot, file);
	const relativePath = path.relative(resolvedRoot, resolvedPath);
	if (
		relativePath === "" ||
		relativePath.startsWith("..") ||
		path.isAbsolute(relativePath)
	) {
		return undefined;
	}
	return resolvedPath;
}

function trimBufferToUtf8Boundary(buffer: Buffer): Buffer {
	if (buffer.length === 0) return buffer;

	let sequenceStart = buffer.length - 1;
	while (sequenceStart >= 0 && (buffer[sequenceStart]! & 0xc0) === 0x80) {
		sequenceStart -= 1;
	}
	if (sequenceStart < 0) return Buffer.alloc(0);

	const leadByte = buffer[sequenceStart]!;
	const continuationBytes = buffer.length - sequenceStart - 1;
	let expectedContinuationBytes = 0;
	if ((leadByte & 0x80) === 0) expectedContinuationBytes = 0;
	else if ((leadByte & 0xe0) === 0xc0) expectedContinuationBytes = 1;
	else if ((leadByte & 0xf0) === 0xe0) expectedContinuationBytes = 2;
	else if ((leadByte & 0xf8) === 0xf0) expectedContinuationBytes = 3;
	else return buffer;

	return continuationBytes < expectedContinuationBytes
		? buffer.subarray(0, sequenceStart)
		: buffer;
}

function getErrorCode(error: unknown): string | undefined {
	return error &&
		typeof error === "object" &&
		"code" in error &&
		typeof (error as { code?: unknown }).code === "string"
		? (error as { code: string }).code
		: undefined;
}

function sanitizeFileReadError(error: unknown, absolutePath: string): string {
	const code = getErrorCode(error);
	if (code === "ENOENT") return "file does not exist in inspection snapshot";
	if (code === "ENOTDIR") {
		return "parent path is not a directory in inspection snapshot";
	}

	const message = error instanceof Error ? error.message : String(error);
	return message.split(absolutePath).join("<inspection path>");
}

function truncateByCodePoints(value: string, maxChars: number): string {
	if (maxChars <= 0) return "";
	const chars = Array.from(value);
	return chars.length <= maxChars ? value : chars.slice(0, maxChars).join("");
}

function closeOpenMarkdownFence(value: string): string {
	const fenceCount = value.match(/^```/gm)?.length ?? 0;
	return fenceCount % 2 === 1 ? `${value}\n\`\`\`` : value;
}

function readContextFilePreview(absolutePath: string): {
	text?: string;
	truncated: boolean;
	binary: boolean;
	error?: string;
} {
	try {
		const stat = fs.statSync(absolutePath);
		if (!stat.isFile()) {
			return {
				truncated: false,
				binary: false,
				error: stat.isDirectory()
					? "path is a directory"
					: "path is not a regular file",
			};
		}

		const fd = fs.openSync(absolutePath, "r");
		try {
			const sample = Buffer.alloc(MAX_CONTEXT_FILE_CHARS + 4);
			const bytesRead = fs.readSync(fd, sample, 0, sample.length, 0);
			const previewSample = trimBufferToUtf8Boundary(
				sample.subarray(0, Math.min(bytesRead, MAX_CONTEXT_FILE_CHARS)),
			);
			if (previewSample.includes(0)) {
				return { truncated: bytesRead > MAX_CONTEXT_FILE_CHARS, binary: true };
			}
			return {
				text: previewSample.toString("utf8").replace(/\r\n/g, "\n"),
				truncated: bytesRead > MAX_CONTEXT_FILE_CHARS,
				binary: false,
			};
		} finally {
			fs.closeSync(fd);
		}
	} catch (error) {
		return {
			truncated: false,
			binary: false,
			error: sanitizeFileReadError(error, absolutePath),
		};
	}
}

function buildRepositoryContextPacket(
	inspectionRoot: string,
	changedFiles: string[],
): { packet: string; wasTruncated: boolean; warnings: string[] } {
	const sections: string[] = [];
	const warnings: string[] = [];
	let remainingChars = MAX_CONTEXT_PACKET_CHARS;
	let wasTruncated = false;

	for (const file of changedFiles) {
		if (remainingChars <= 0) {
			wasTruncated = true;
			break;
		}

		const absolutePath = resolvePathUnderRoot(inspectionRoot, file);
		if (!absolutePath) {
			warnings.push(`Skipped repository context for path outside inspection root: ${file}`);
			continue;
		}

		const preview = readContextFilePreview(absolutePath);
		let section: string;
		if (preview.error) {
			section = [`### ${file}`, `Context unavailable: ${preview.error}`].join("\n");
		} else if (preview.binary) {
			section = [`### ${file}`, "Binary file context omitted."].join("\n");
		} else {
			const truncatedLine = preview.truncated
				? "\n\n[repository context for this file truncated]"
				: "";
			section = [
				`### ${file}`,
				"```text",
				`${preview.text ?? ""}${truncatedLine}`,
				"```",
			].join("\n");
		}

		if (section.length > remainingChars) {
			const truncatedSection = closeOpenMarkdownFence(
				truncateByCodePoints(section, remainingChars),
			);
			sections.push(
				`${truncatedSection}\n\n[repository context packet truncated]`,
			);
			wasTruncated = true;
			remainingChars = 0;
			break;
		}

		sections.push(section);
		remainingChars -= section.length + 2;
	}

	return {
		packet: sections.join("\n\n"),
		wasTruncated,
		warnings,
	};
}

function withInspectionContext(
	context: ReviewContext,
	snapshot: InspectionSnapshot,
): ReviewContext {
	const repositoryContext = buildRepositoryContextPacket(
		snapshot.root,
		context.changedFiles,
	);
	return {
		...context,
		inspectionRoot: snapshot.root,
		inspectionRootDescription: snapshot.description,
		repositoryContextPacket: repositoryContext.packet,
		repositoryContextWasTruncated: repositoryContext.wasTruncated,
		inspectionWarnings: [
			...context.inspectionWarnings,
			...(snapshot.warnings ?? []),
			...repositoryContext.warnings,
		],
	};
}

async function collectDiffReviewContext(
	pi: ExtensionAPI,
	repoRoot: string,
	options: DiffReviewContextOptions,
	signal?: AbortSignal,
): Promise<ReviewContext> {
	const diffBaseArgs = [
		"diff",
		...(options.diffMode === "staged" ? ["--cached"] : []),
	];
	const statusArgs = ["status", "--short", "--untracked-files=all"];
	const untrackedPromise =
		options.diffMode === "working-tree"
			? runGit(
					pi,
					repoRoot,
					["ls-files", "--others", "--exclude-standard"],
					signal,
				)
			: Promise.resolve({ stdout: "", stderr: "", code: 0 });

	const [statusResult, statResult, filesResult, diffResult, untrackedResult] =
		await Promise.all([
			runGit(pi, repoRoot, statusArgs, signal),
			runGit(
				pi,
				repoRoot,
				[...diffBaseArgs, "--stat", options.diffBaseRef],
				signal,
			),
			runGit(
				pi,
				repoRoot,
				[...diffBaseArgs, "--name-only", options.diffBaseRef],
				signal,
			),
			runGit(
				pi,
				repoRoot,
				[...diffBaseArgs, "--unified=3", options.diffBaseRef],
				signal,
			),
			untrackedPromise,
		]);

	if (
		statResult.code !== 0 ||
		filesResult.code !== 0 ||
		diffResult.code !== 0 ||
		untrackedResult.code !== 0
	) {
		const errorText = [
			statResult.stderr,
			filesResult.stderr,
			diffResult.stderr,
			untrackedResult.stderr,
		]
			.map((part) => part.trim())
			.filter(Boolean)
			.join("\n");
		throw new Error(errorText || "Failed to collect git diff for review.");
	}

	const diffFiles = filesResult.stdout
		.split("\n")
		.map((line) => line.trim())
		.filter(Boolean);
	const untrackedFiles = untrackedResult.stdout
		.split("\n")
		.map((line) => line.trim())
		.filter(Boolean);
	const changedFiles = uniqueNonEmptyStrings([...diffFiles, ...untrackedFiles]);

	if (changedFiles.length === 0) {
		throw new Error("No matching changes to review.");
	}

	const diffStat = [
		statResult.stdout.trim(),
		formatUntrackedDiffStat(untrackedFiles),
	]
		.filter(Boolean)
		.join("\n\n");
	const fullDiff = buildCombinedDiffPreview(
		repoRoot,
		diffResult.stdout.trim(),
		untrackedFiles,
	);
	const diffWasTruncated = fullDiff.length > MAX_DIFF_CHARS;
	const diffPreview = diffWasTruncated
		? `${fullDiff.slice(0, MAX_DIFF_CHARS)}\n\n[diff truncated]`
		: fullDiff;

	const baseContext: ReviewContext = {
		repoRoot,
		inspectionRoot: repoRoot,
		inspectionRootDescription: "working tree",
		target: options.targetLabel,
		baseRef: options.displayBaseRef,
		statusShort: statusResult.stdout.trim(),
		diffStat,
		changedFiles,
		diffPreview,
		diffWasTruncated,
		repositoryContextPacket: "",
		repositoryContextWasTruncated: false,
		inspectionWarnings: [],
	};

	if (options.includeRepositoryContext === false) return baseContext;

	return withInspectionContext(baseContext, {
		root: repoRoot,
		description: "working tree",
	});
}

async function resolveCommitRef(
	pi: ExtensionAPI,
	repoRoot: string,
	sha: string,
	signal?: AbortSignal,
): Promise<{ sha: string; title?: string }> {
	const trimmedSha = sha.trim();
	if (!trimmedSha) throw new Error("Commit sha is required.");

	const commitResult = await runGit(
		pi,
		repoRoot,
		["rev-parse", "--verify", "--quiet", `${trimmedSha}^{commit}`],
		signal,
	);
	if (commitResult.code !== 0) {
		throw new Error(`Invalid or unknown commit: ${trimmedSha}`);
	}

	const resolvedSha = commitResult.stdout.trim();
	const titleResult = await runGit(
		pi,
		repoRoot,
		["show", "-s", "--format=%s", resolvedSha],
		signal,
	);

	return {
		sha: resolvedSha,
		title: titleResult.code === 0 ? titleResult.stdout.trim() || undefined : undefined,
	};
}

async function collectCommitReviewContext(
	pi: ExtensionAPI,
	repoRoot: string,
	sha: string,
	signal?: AbortSignal,
	includeRepositoryContext = true,
): Promise<ReviewContext> {
	const commit = await resolveCommitRef(pi, repoRoot, sha, signal);
	const [statResult, filesResult, diffResult] = await Promise.all([
		runGit(pi, repoRoot, ["show", "--stat", "--format=", commit.sha], signal),
		runGit(pi, repoRoot, ["show", "--name-only", "--format=", commit.sha], signal),
		runGit(pi, repoRoot, ["show", "--unified=3", "--format=", commit.sha], signal),
	]);

	if (
		statResult.code !== 0 ||
		filesResult.code !== 0 ||
		diffResult.code !== 0
	) {
		const errorText = [statResult.stderr, filesResult.stderr, diffResult.stderr]
			.map((part) => part.trim())
			.filter(Boolean)
			.join("\n");
		throw new Error(errorText || `Failed to collect commit diff for review: ${sha}`);
	}

	const changedFiles = uniqueNonEmptyStrings(filesResult.stdout.split("\n"));
	if (changedFiles.length === 0) {
		throw new Error(`Commit has no file changes to review: ${commit.sha}`);
	}

	const fullDiff = diffResult.stdout.trim();
	const diffWasTruncated = fullDiff.length > MAX_DIFF_CHARS;
	const diffPreview = diffWasTruncated
		? `${fullDiff.slice(0, MAX_DIFF_CHARS)}\n\n[diff truncated]`
		: fullDiff;
	const shortSha = commit.sha.slice(0, 12);
	const targetLabel = commit.title
		? `commit ${shortSha}: ${commit.title}`
		: `commit ${shortSha}`;

	const baseContext: ReviewContext = {
		repoRoot,
		inspectionRoot: repoRoot,
		inspectionRootDescription: "working tree",
		target: targetLabel,
		baseRef: commit.sha,
		statusShort: "(not applicable: commit review)",
		diffStat: statResult.stdout.trim(),
		changedFiles,
		diffPreview,
		diffWasTruncated,
		repositoryContextPacket: "",
		repositoryContextWasTruncated: false,
		inspectionWarnings: [],
	};

	if (!includeRepositoryContext) return baseContext;

	return withInspectionContext(baseContext, {
		root: repoRoot,
		description: "working tree",
	});
}

async function collectReviewContextForTarget(
	pi: ExtensionAPI,
	cwd: string,
	target: ReviewTarget,
	signal?: AbortSignal,
): Promise<{ context: ReviewContext; cleanup?: () => Promise<void> }> {
	const repoRoot = await resolveRepoRoot(pi, cwd, signal);

	switch (target.type) {
		case "uncommitted": {
			const resolved = await resolveBaseRef(pi, repoRoot, "HEAD", signal);
			return {
				context: await collectDiffReviewContext(
					pi,
					repoRoot,
					{
						targetLabel: "uncommitted changes",
						diffMode: "working-tree",
						diffBaseRef: resolved.diffBaseRef,
						displayBaseRef: resolved.displayBaseRef,
					},
					signal,
				),
			};
		}
		case "staged": {
			const resolved = await resolveBaseRef(pi, repoRoot, "HEAD", signal);
			const baseContext = await collectDiffReviewContext(
				pi,
				repoRoot,
				{
					targetLabel: "staged changes",
					diffMode: "staged",
					diffBaseRef: resolved.diffBaseRef,
					displayBaseRef: resolved.displayBaseRef,
					includeRepositoryContext: false,
				},
				signal,
			);
			const snapshot = await createStagedInspectionSnapshot(pi, repoRoot, signal);
			return {
				context: withInspectionContext(baseContext, snapshot),
				cleanup: snapshot.cleanup,
			};
		}
		case "baseBranch": {
			const resolved = await resolveMergeBase(
				pi,
				repoRoot,
				target.branch,
				signal,
			);
			return {
				context: await collectDiffReviewContext(
					pi,
					repoRoot,
					{
						targetLabel: `base branch ${target.branch.trim()}`,
						diffMode: "working-tree",
						diffBaseRef: resolved.diffBaseRef,
						displayBaseRef: resolved.displayBaseRef,
					},
					signal,
				),
			};
		}
		case "commit": {
			const baseContext = await collectCommitReviewContext(
				pi,
				repoRoot,
				target.sha,
				signal,
				false,
			);
			const snapshot = await createCommitInspectionSnapshot(
				pi,
				repoRoot,
				baseContext.baseRef,
				signal,
			);
			return {
				context: withInspectionContext(baseContext, snapshot),
				cleanup: snapshot.cleanup,
			};
		}
	}
}

function buildReviewerDiffPreview(
	context: ReviewContext,
	reviewer: ReviewerConfig,
): { preview: string; wasTruncated: boolean } {
	const maxDiffChars = reviewer.maxDiffChars ?? MAX_DIFF_CHARS;
	if (context.diffPreview.length <= maxDiffChars) {
		return {
			preview: context.diffPreview,
			wasTruncated: context.diffWasTruncated,
		};
	}

	return {
		preview: `${context.diffPreview.slice(0, maxDiffChars)}\n\n[diff truncated for reviewer prompt budget]`,
		wasTruncated: true,
	};
}

function buildReviewBriefDiffPreview(
	context: ReviewContext,
): { preview: string; wasTruncated: boolean } {
	const maxDiffChars = 40_000;
	if (context.diffPreview.length <= maxDiffChars) {
		return {
			preview: context.diffPreview,
			wasTruncated: context.diffWasTruncated,
		};
	}
	return {
		preview: `${context.diffPreview.slice(0, maxDiffChars)}\n\n[diff truncated for brief prompt budget]`,
		wasTruncated: true,
	};
}

export function buildReviewBriefTask(
	context: ReviewContext,
	extraPrompt?: string,
): string {
	const changedFilesText = context.changedFiles
		.map((file) => `- ${file}`)
		.join("\n");
	const briefDiff = buildReviewBriefDiffPreview(context);
	const lines: string[] = [
		`Working directory: ${context.inspectionRoot}`,
		`Repository root: ${context.repoRoot}`,
		`Inspection root for read/grep/find/ls/bash: ${context.inspectionRoot}`,
		`Inspection root kind: ${context.inspectionRootDescription}`,
		`For repository-local investigation, only inspect paths under ${context.inspectionRoot}.`,
		"Create a concise orientation brief for later code review agents.",
		"This is not the final review. Do not decide whether the change is correct; summarize intent, scope, and risk areas to investigate.",
		"Use the diff and repository context packet as the primary evidence. Inspect repository files only if needed to understand intent or risk.",
		"Clearly label assumptions and unknowns; do not present guesses as facts.",
	];

	if (extraPrompt?.trim()) {
		lines.push("", "Additional briefing context:", extraPrompt.trim());
	}

	if (context.inspectionWarnings.length > 0) {
		lines.push("", "Inspection notes:");
		for (const warning of context.inspectionWarnings) lines.push(`- ${warning}`);
	}

	lines.push(
		"",
		"Return markdown with exactly these sections:",
		"## Intended Goal",
		"A short paragraph describing what the change appears intended to achieve.",
		"",
		"## Main Changes",
		"- Bullets describing the important implementation changes.",
		"",
		"## Risk Areas for Reviewers",
		"- Bullets naming behavior, files, contracts, or edge cases reviewers should scrutinize.",
		"",
		"## Important Context",
		"- Bullets with contextual facts that help reviewers understand the change.",
		"",
		"## Unknowns / Assumptions",
		"- Bullets for anything uncertain. If there are none, write `- None`.",
		"",
		"Review context:",
		`- Target: ${context.target}`,
		`- Base ref: ${context.baseRef}`,
		`- Repo root: ${context.repoRoot}`,
		`- Inspection root: ${context.inspectionRoot}`,
		`- Inspection root kind: ${context.inspectionRootDescription}`,
		`- Diff truncated: ${briefDiff.wasTruncated ? "yes" : "no"}`,
		`- Repository context packet truncated: ${context.repositoryContextWasTruncated ? "yes" : "no"}`,
		"",
		"Changed files:",
		changedFilesText,
		"",
		"Repository context packet:",
		context.repositoryContextPacket || "(no repository context packet available)",
		"",
		"Git status (--short):",
		context.statusShort || "(clean status output)",
		"",
		"Diff stat:",
		context.diffStat || "(no diff stat)",
		"",
		"Diff preview:",
		briefDiff.preview || "(no diff)",
	);

	return lines.join("\n");
}

export function buildReviewTask(
	context: ReviewContext,
	reviewer: ReviewerConfig,
	extraPrompt?: string,
): string {
	const changedFilesText = context.changedFiles
		.map((file) => `- ${file}`)
		.join("\n");
	const focus = reviewer.focus?.trim() || "general code review";
	const reviewerDiff = buildReviewerDiffPreview(context, reviewer);
	const lines: string[] = [
		`Working directory: ${context.inspectionRoot}`,
		`Repository root: ${context.repoRoot}`,
		`Inspection root for read/grep/find/ls/bash: ${context.inspectionRoot}`,
		`Inspection root kind: ${context.inspectionRootDescription}`,
		`For repository-local investigation, only inspect paths under ${context.inspectionRoot}.`,
		`Review focus: ${focus}`,
		"Review only the code changes described below.",
		"Use the diff as the primary review target, but inspect unchanged surrounding code whenever it affects whether a finding is real.",
		"You have read-only repository inspection tools: read, grep, find, ls, and read-only bash/git.",
		"Use those tools to inspect changed files, definitions, callers, tests, configuration, schemas, or contracts when a finding depends on code outside the shown diff.",
		"Do not rely solely on the diff when unchanged repository code could confirm or refute an issue.",
		"Before reporting an actionable finding, verify it against the actual repository state available under the inspection root.",
		"If the diff and repository context packet are sufficient and no further inspection is needed, say so briefly in the Summary.",
		"If the diff preview or repository context packet is truncated, use repo-local inspection tools to verify the exact code before reporting a finding.",
		"The changed files list may include untracked working-tree files, which are also included in the review context below.",
		"Only report actionable issues that are reasonably likely to be real.",
		"Do not report style-only nits unless the prompt explicitly asks for them.",
		"If you think there are no actionable issues, say so clearly.",
		"Emit one short [[progress]] block early in the review, then update it only if your plan materially changes.",
	];

	if (extraPrompt?.trim()) {
		lines.push("", "Additional review instructions:", extraPrompt.trim());
	}

	if (context.inspectionWarnings.length > 0) {
		lines.push("", "Inspection notes:");
		for (const warning of context.inspectionWarnings) lines.push(`- ${warning}`);
	}

	if (context.changeBrief?.trim()) {
		lines.push(
			"",
			"Change brief from a separate summarizer:",
			"Treat this brief as orientation only. Verify all claims independently against the diff and repository state.",
			context.changeBrief.trim(),
		);
	}
	if ((context.changeBriefWarnings ?? []).length > 0) {
		lines.push("", "Change brief notes:");
		for (const warning of context.changeBriefWarnings ?? []) lines.push(`- ${warning}`);
	}

	lines.push(
		"",
		"Review standards:",
		"- Flag only actionable issues the author would likely fix if they knew about them.",
		"- Prefer correctness, regressions, hidden bugs, safety issues, and meaningful maintainability concerns over style nits.",
		"- Do not speculate beyond the evidence available in the diff and surrounding code.",
		"- Treat silent fallback behavior, swallowed errors, and best-effort recovery as high-signal findings unless the boundary explicitly justifies them.",
		"- Surface informational non-blocking callouts separately from actionable findings.",
		"",
		"Return markdown with exactly these sections:",
		"## Summary",
		"A short paragraph describing the overall review conclusion.",
		"",
		"## Verdict",
		"Write exactly one of: `correct` or `needs attention`.",
		"",
		"## Findings",
		"- One bullet per actionable finding.",
		"- Format each bullet as: `[severity: high|medium|low][confidence: high|medium|low][path: <file or file:line>] issue | evidence | recommendation`",
		"- If there are no actionable findings, write `- None`.",
		"",
		"## Non-blocking Callouts",
		"- Use bullets for non-blocking informational callouts such as migrations, dependency or lockfile changes, auth/permission changes, config-default changes, backwards-incompatible contract/schema/API updates, and destructive operations.",
		"- Do not repeat actionable findings here.",
		"- If there are no applicable callouts, write `- None`.",
		"",
		"## Next Steps",
		"- Optional follow-up suggestions. Use bullets. If there are none, write `- None`.",
		"",
		"Review context:",
		`- Target: ${context.target}`,
		`- Base ref: ${context.baseRef}`,
		`- Repo root: ${context.repoRoot}`,
		`- Inspection root: ${context.inspectionRoot}`,
		`- Inspection root kind: ${context.inspectionRootDescription}`,
		`- Diff truncated: ${reviewerDiff.wasTruncated ? "yes" : "no"}`,
		`- Repository context packet truncated: ${context.repositoryContextWasTruncated ? "yes" : "no"}`,
		"",
		"Changed files:",
		changedFilesText,
		"",
		"Repository context packet (unchanged surrounding code from the inspection root):",
		context.repositoryContextPacket || "(no repository context packet available)",
		"",
		"Git status (--short):",
		context.statusShort || "(clean status output)",
		"",
		"Diff stat:",
		context.diffStat || "(no diff stat)",
		"",
		"Diff preview:",
		reviewerDiff.preview || "(no diff)",
	);

	return lines.join("\n");
}

export function withReviewChangeBrief(
	context: ReviewContext,
	changeBrief: string | undefined,
	warnings: string[] = [],
): ReviewContext {
	return {
		...context,
		changeBrief: changeBrief?.trim() || undefined,
		changeBriefWarnings: warnings,
	};
}

async function buildAdditionalReviewInstructions(
	params: ReviewRequest,
	cwd: string,
): Promise<string | undefined> {
	const projectGuidelines = await loadProjectReviewGuidelines(cwd);
	return composeAdditionalReviewInstructions({
		extraPrompt: params.prompt,
		projectGuidelines,
	});
}

export async function createReviewBriefTask(
	context: ReviewContext,
	params: ReviewRequest,
	defaultCwd: string,
): Promise<SubagentTaskInput> {
	const cwd = params.cwd?.trim() || defaultCwd;
	const additionalInstructions = await buildAdditionalReviewInstructions(params, cwd);
	return {
		task: buildReviewBriefTask(context, additionalInstructions),
		label: "Change brief",
		model: FAST_EXPLORE_MODEL,
		thinkingLevel: "medium",
		cwd: context.inspectionRoot,
		metadata: {
			brief: true,
			focus: "change intent, scope, and risk areas",
		},
	};
}

export async function createReviewTasksForContext(
	context: ReviewContext,
	params: ReviewRequest,
	defaultCwd: string,
): Promise<SubagentTaskInput[]> {
	const cwd = params.cwd?.trim() || defaultCwd;
	const reviewers = [...DEFAULT_REVIEWERS];
	const additionalInstructions = await buildAdditionalReviewInstructions(params, cwd);
	return reviewers.map((reviewer) => ({
		task: buildReviewTask(context, reviewer, additionalInstructions),
		label: reviewer.label?.trim() || reviewer.model,
		model: reviewer.model.trim(),
		thinkingLevel: reviewer.thinkingLevel,
		cwd: context.inspectionRoot,
		metadata: {
			focus: reviewer.focus?.trim() || undefined,
			reviewerLabel: reviewer.label?.trim() || reviewer.model.trim(),
			thinkingLevel: reviewer.thinkingLevel,
			maxDiffChars: reviewer.maxDiffChars,
		},
	}));
}

export async function createReviewContext(
	pi: ExtensionAPI,
	params: ReviewCommandRequest,
	defaultCwd: string,
	signal?: AbortSignal,
): Promise<{ context: ReviewContext; cleanup?: () => Promise<void> }> {
	const cwd = params.cwd?.trim() || defaultCwd;
	return collectReviewContextForTarget(pi, cwd, params.target, signal);
}

export async function createReviewTasks(
	pi: ExtensionAPI,
	params: ReviewCommandRequest,
	defaultCwd: string,
	signal?: AbortSignal,
): Promise<{
	tasks: SubagentTaskInput[];
	context: ReviewContext;
	cleanup?: () => Promise<void>;
}> {
	let cleanup: (() => Promise<void>) | undefined;
	try {
		const collected = await createReviewContext(pi, params, defaultCwd, signal);
		const { context } = collected;
		cleanup = collected.cleanup;
		return {
			context,
			cleanup,
			tasks: await createReviewTasksForContext(context, params, defaultCwd),
		};
	} catch (error) {
		await cleanupQuietly(cleanup);
		throw error;
	}
}

const INLINE_CHANGED_FILES_LIMIT = 8;
const REVIEW_SECTION_TITLES = {
	summary: "Summary",
	verdict: "Verdict",
	findings: "Findings",
	nonBlockingCallouts: "Non-blocking Callouts",
	legacyHumanReviewerCallouts: "Human Reviewer Callouts",
	nextSteps: "Next Steps",
} as const;
const REVIEW_SECTION_CANONICAL_TITLES = {
	summary: REVIEW_SECTION_TITLES.summary,
	verdict: REVIEW_SECTION_TITLES.verdict,
	findings: REVIEW_SECTION_TITLES.findings,
	"non-blocking callouts": REVIEW_SECTION_TITLES.nonBlockingCallouts,
	"next steps": REVIEW_SECTION_TITLES.nextSteps,
} as const;
const REVIEW_EXPECTED_SECTION_ORDER = [
	"summary",
	"verdict",
	"findings",
	"non-blocking callouts",
	"next steps",
] as const;
const REVIEW_SECTION_ALIASES = new Map<string, keyof typeof REVIEW_SECTION_CANONICAL_TITLES>([
	["human reviewer callouts", "non-blocking callouts"],
]);

type ReviewSectionKey = keyof typeof REVIEW_SECTION_CANONICAL_TITLES;

type ParsedReviewSections = {
	sections: Map<ReviewSectionKey, string>;
	sectionOrder: ReviewSectionKey[];
	preamble: string;
	unexpectedSections: string[];
	duplicateSections: string[];
};

function normalizeOptionalBullets(sectionBody: string | undefined): string[] {
	return (parseBullets(sectionBody) ?? []).filter(
		(item) => item.toLowerCase() !== "none",
	);
}

function parseVerdict(sectionBody: string | undefined): string | undefined {
	const line = sectionBody
		?.split("\n")
		.map((item) => item.trim())
		.find(Boolean)
		?.toLowerCase();
	return line === "correct" || line === "needs attention" ? line : undefined;
}

function asStringArray(value: unknown): string[] {
	return Array.isArray(value)
		? value.filter((item): item is string => typeof item === "string")
		: [];
}

function parseReviewSections(markdown: string): ParsedReviewSections {
	const normalized = markdown.trim();
	const sectionRegex = /^##\s+(.+)$/gm;
	const matches = [...normalized.matchAll(sectionRegex)];
	const sections = new Map<ReviewSectionKey, string>();
	const sectionOrder: ReviewSectionKey[] = [];
	const unexpectedSections: string[] = [];
	const duplicateSections: string[] = [];

	if (matches.length === 0) {
		return {
			sections,
			sectionOrder,
			preamble: normalized,
			unexpectedSections,
			duplicateSections,
		};
	}

	const preamble = normalized.slice(0, matches[0]!.index!).trim();
	for (let i = 0; i < matches.length; i++) {
		const match = matches[i]!;
		const rawTitle = match[1]!.trim();
		const normalizedTitle = rawTitle.toLowerCase();
		const canonicalTitle =
			REVIEW_SECTION_ALIASES.get(normalizedTitle) ??
			(normalizedTitle in REVIEW_SECTION_CANONICAL_TITLES
				? (normalizedTitle as ReviewSectionKey)
				: undefined);
		const start = match.index! + match[0].length;
		const end =
			i + 1 < matches.length ? matches[i + 1]!.index! : normalized.length;
		const body = normalized.slice(start, end).trim();

		if (!canonicalTitle) {
			unexpectedSections.push(rawTitle);
			continue;
		}
		if (sections.has(canonicalTitle)) {
			duplicateSections.push(rawTitle);
			continue;
		}

		sections.set(canonicalTitle, body);
		sectionOrder.push(canonicalTitle);
	}

	return {
		sections,
		sectionOrder,
		preamble,
		unexpectedSections,
		duplicateSections,
	};
}

function buildReviewParseMeta(
	markdown: string,
	parsedSections: ParsedReviewSections,
	verdict: string | undefined,
): ParsedOutputMeta {
	const missingSections: string[] = [];
	for (const key of REVIEW_EXPECTED_SECTION_ORDER) {
		if (!parsedSections.sections.has(key)) {
			missingSections.push(REVIEW_SECTION_CANONICAL_TITLES[key]);
		}
	}
	if (
		parsedSections.sections.has("verdict") &&
		!verdict &&
		!missingSections.includes(REVIEW_SECTION_TITLES.verdict)
	) {
		missingSections.push(REVIEW_SECTION_TITLES.verdict);
	}

	const warnings: string[] = [];
	const recognizedSectionCount = REVIEW_EXPECTED_SECTION_ORDER.filter((key) =>
		parsedSections.sections.has(key),
	).length;
	if (recognizedSectionCount === 0) {
		warnings.push("No expected review sections were found.");
	}
	if (parsedSections.preamble) {
		warnings.push("Unexpected preamble before ## Summary.");
	}
	if (parsedSections.unexpectedSections.length > 0) {
		warnings.push(
			`Unexpected top-level sections: ${parsedSections.unexpectedSections.join(", ")}.`,
		);
	}
	if (parsedSections.duplicateSections.length > 0) {
		warnings.push(
			`Duplicate top-level sections: ${parsedSections.duplicateSections.join(", ")}.`,
		);
	}
	if (
		recognizedSectionCount > 0 &&
		parsedSections.sectionOrder.join("|") !== REVIEW_EXPECTED_SECTION_ORDER.join("|")
	) {
		warnings.push(
			`Unexpected section order. Expected: ${REVIEW_EXPECTED_SECTION_ORDER.map((key) => `## ${REVIEW_SECTION_CANONICAL_TITLES[key]}`).join(" -> ")}.`,
		);
	}
	if (/<\/?(?:details|summary)\b/i.test(markdown)) {
		warnings.push("Output contains HTML-style disclosure markup.");
	}
	if (/<\/?(?:read_file|path|grep|find|ls|bash|tool|function_calls?)>/i.test(markdown)) {
		warnings.push("Output contains XML-like or tool-trace content.");
	}

	const structure =
		recognizedSectionCount === REVIEW_EXPECTED_SECTION_ORDER.length &&
			verdict &&
			warnings.length === 0
			? "valid"
			: recognizedSectionCount > 0
				? "partial"
				: "invalid";

	return {
		structure,
		missingSections,
		warnings,
	};
}

function inferReviewParseMeta(result: SubagentTaskResult): ParsedOutputMeta {
	if (result.parseMeta) {
		return {
			structure: result.parseMeta.structure,
			missingSections: [...(result.parseMeta.missingSections ?? [])],
			warnings: [...(result.parseMeta.warnings ?? [])],
		};
	}

	const hasStructuredFields =
		result.summary.trim().length > 0 ||
		Object.values(result.data ?? {}).some((value) => {
			if (Array.isArray(value)) return value.length > 0;
			if (typeof value === "string") return value.trim().length > 0;
			return Boolean(value);
		});
	return {
		structure: hasStructuredFields ? "partial" : "invalid",
		missingSections: [],
		warnings: [],
	};
}

function buildParseIssues(parseMeta: ParsedOutputMeta): string[] {
	return [
		...(parseMeta.missingSections ?? []).map(
			(section) => `Missing section: ${section}`,
		),
		...(parseMeta.warnings ?? []),
	];
}

function pushBulletSection(
	lines: string[],
	title: string,
	items: string[],
	emptyText = "- None",
): void {
	lines.push(title);
	if (items.length > 0) {
		for (const item of items) lines.push(`- ${item}`);
	} else {
		lines.push(emptyText);
	}
	lines.push("");
}

function renderTextFence(text: string): string[] {
	const trimmed = text.trim();
	const fenceLength = Math.max(
		3,
		...((trimmed.match(/`+/g) ?? []).map((run) => run.length + 1) as number[]),
	);
	const fence = "`".repeat(fenceLength);
	return [`${fence}text`, trimmed || "(empty)", fence];
}

const REVIEW_BRIEF_EXPECTED_SECTION_ORDER = [
	"intended goal",
	"main changes",
	"risk areas for reviewers",
	"important context",
	"unknowns / assumptions",
] as const;
const REVIEW_BRIEF_SECTION_TITLES = {
	"intended goal": "Intended Goal",
	"main changes": "Main Changes",
	"risk areas for reviewers": "Risk Areas for Reviewers",
	"important context": "Important Context",
	"unknowns / assumptions": "Unknowns / Assumptions",
} as const;

type ReviewBriefSectionKey = (typeof REVIEW_BRIEF_EXPECTED_SECTION_ORDER)[number];

function parseReviewBriefSections(markdown: string): {
	sections: Map<ReviewBriefSectionKey, string>;
	sectionOrder: ReviewBriefSectionKey[];
	preamble: string;
	unexpectedSections: string[];
	duplicateSections: string[];
} {
	const normalized = markdown.trim();
	const sectionRegex = /^##\s+(.+)$/gm;
	const matches = [...normalized.matchAll(sectionRegex)];
	const sections = new Map<ReviewBriefSectionKey, string>();
	const sectionOrder: ReviewBriefSectionKey[] = [];
	const unexpectedSections: string[] = [];
	const duplicateSections: string[] = [];

	if (matches.length === 0) {
		return {
			sections,
			sectionOrder,
			preamble: normalized,
			unexpectedSections,
			duplicateSections,
		};
	}

	const preamble = normalized.slice(0, matches[0]!.index!).trim();
	for (let i = 0; i < matches.length; i++) {
		const match = matches[i]!;
		const rawTitle = match[1]!.trim();
		const normalizedTitle = rawTitle.toLowerCase();
		const canonicalTitle = REVIEW_BRIEF_EXPECTED_SECTION_ORDER.includes(
			normalizedTitle as ReviewBriefSectionKey,
		)
			? (normalizedTitle as ReviewBriefSectionKey)
			: undefined;
		const start = match.index! + match[0].length;
		const end =
			i + 1 < matches.length ? matches[i + 1]!.index! : normalized.length;
		const body = normalized.slice(start, end).trim();

		if (!canonicalTitle) {
			unexpectedSections.push(rawTitle);
			continue;
		}
		if (sections.has(canonicalTitle)) {
			duplicateSections.push(rawTitle);
			continue;
		}

		sections.set(canonicalTitle, body);
		sectionOrder.push(canonicalTitle);
	}

	return { sections, sectionOrder, preamble, unexpectedSections, duplicateSections };
}

export function parseReviewBriefOutput(markdown: string): ParsedSubagentOutput {
	const normalized = markdown.trim();
	if (!normalized) {
		return {
			summary: "",
			data: { changeBriefMarkdown: "" },
			parseMeta: {
				structure: "invalid",
				missingSections: Object.values(REVIEW_BRIEF_SECTION_TITLES),
				warnings: ["Empty review brief output."],
			},
		};
	}

	const parsed = parseReviewBriefSections(normalized);
	const missingSections = REVIEW_BRIEF_EXPECTED_SECTION_ORDER
		.filter((key) => !parsed.sections.has(key))
		.map((key) => REVIEW_BRIEF_SECTION_TITLES[key]);
	const warnings: string[] = [];
	if (parsed.preamble) warnings.push("Unexpected preamble before ## Intended Goal.");
	if (parsed.unexpectedSections.length > 0) {
		warnings.push(
			`Unexpected top-level sections: ${parsed.unexpectedSections.join(", ")}.`,
		);
	}
	if (parsed.duplicateSections.length > 0) {
		warnings.push(
			`Duplicate top-level sections: ${parsed.duplicateSections.join(", ")}.`,
		);
	}
	if (
		parsed.sectionOrder.length > 0 &&
		parsed.sectionOrder.join("|") !== REVIEW_BRIEF_EXPECTED_SECTION_ORDER.join("|")
	) {
		warnings.push(
			`Unexpected section order. Expected: ${REVIEW_BRIEF_EXPECTED_SECTION_ORDER.map((key) => `## ${REVIEW_BRIEF_SECTION_TITLES[key]}`).join(" -> ")}.`,
		);
	}

	const recognizedSectionCount = REVIEW_BRIEF_EXPECTED_SECTION_ORDER.filter((key) =>
		parsed.sections.has(key),
	).length;
	const structure =
		recognizedSectionCount === REVIEW_BRIEF_EXPECTED_SECTION_ORDER.length &&
		warnings.length === 0
			? "valid"
			: recognizedSectionCount > 0
				? "partial"
				: "invalid";
	const intendedGoal = parsed.sections.get("intended goal") ?? "";
	const summary = structure === "invalid" ? normalized.split("\n")[0]!.trim() : intendedGoal;

	return {
		summary,
		data: {
			changeBriefMarkdown: normalized,
			riskAreas: normalizeOptionalBullets(
				parsed.sections.get("risk areas for reviewers"),
			),
		},
		parseMeta: { structure, missingSections, warnings },
	};
}

export function parseReviewOutput(markdown: string): ParsedSubagentOutput {
	const normalized = markdown.trim();
	if (!normalized) {
		return {
			summary: "",
			data: {
				verdict: undefined,
				findings: [],
				humanReviewerCallouts: [],
				suggestedNextSteps: [],
			},
			parseMeta: {
				structure: "invalid",
				missingSections: [
					REVIEW_SECTION_TITLES.summary,
					REVIEW_SECTION_TITLES.verdict,
					REVIEW_SECTION_TITLES.findings,
					REVIEW_SECTION_TITLES.nonBlockingCallouts,
					REVIEW_SECTION_TITLES.nextSteps,
				],
				warnings: ["Empty review output."],
			},
		};
	}

	const parsedSections = parseReviewSections(normalized);
	const findings = normalizeOptionalBullets(parsedSections.sections.get("findings"));
	const humanReviewerCallouts = normalizeOptionalBullets(
		parsedSections.sections.get("non-blocking callouts"),
	);
	const suggestedNextSteps = normalizeOptionalBullets(
		parsedSections.sections.get("next steps"),
	);
	const verdict = parseVerdict(parsedSections.sections.get("verdict"));
	const parseMeta = buildReviewParseMeta(normalized, parsedSections, verdict);
	const summary =
		parseMeta.structure === "invalid"
			? ""
			: (parsedSections.sections.get("summary") ?? "");

	return {
		summary,
		data: {
			verdict,
			findings,
			humanReviewerCallouts,
			suggestedNextSteps,
		},
		parseMeta,
	};
}

export function buildReviewRepairPrompt(
	parsed: ParsedSubagentOutput,
	rawResponse: string,
): string | undefined {
	if (!parsed.parseMeta || parsed.parseMeta.structure === "valid") return undefined;

	const issues = buildParseIssues(parsed.parseMeta);
	const issueLines = issues.length > 0
		? issues.map((item) => `- ${item}`)
		: ["- Formatting drift detected."];
	const rawPreview = rawResponse
		.trim()
		.split("\n")
		.slice(0, 8)
		.map((line) => `> ${line}`);

	return [
		"Your previous answer did not follow the required review output format.",
		`Structured output status: ${parsed.parseMeta.structure}.`,
		"Rewrite your final answer only.",
		"Start with `## Summary` on the first non-empty line.",
		"Do not include tool narration, XML-like tags, progress blocks, `<details>` blocks, extra headings, or any preamble.",
		"Preserve the substance of your review unless the evidence requires a correction.",
		"",
		"Formatting issues to fix:",
		...issueLines,
		"",
		"Return markdown with exactly these sections in this order:",
		"## Summary",
		"## Verdict",
		"## Findings",
		`## ${REVIEW_SECTION_TITLES.nonBlockingCallouts}`,
		"## Next Steps",
		"",
		"If there are no items for a bullet-list section, write `- None`.",
		"Write exactly one of `correct` or `needs attention` under `## Verdict`.",
		"Do not add any commentary before or after those sections.",
		"",
		"Do not repeat the malformed formatting below. It is included only as a reminder of what to repair:",
		...rawPreview,
	].join("\n");
}

export function renderFinalReviewResults(
	runId: string,
	mode: "single" | "parallel",
	results: SubagentTaskResult[],
	context?: ReviewContext,
): string {
	const lines: string[] = [];
	lines.push("# Review Results");
	lines.push("");
	lines.push(`- Run ID: ${runId}`);
	lines.push(`- Mode: ${mode}`);
	if (context) {
		lines.push(`- Target: ${context.target}`);
		lines.push(`- Base ref: ${context.baseRef}`);
		lines.push(`- Repo root: ${shortenPath(context.repoRoot)}`);
		lines.push(`- Inspection root: ${shortenPath(context.inspectionRoot)} (${context.inspectionRootDescription})`);
		lines.push(`- Change brief: ${context.changeBrief?.trim() ? "available" : "not available"}`);
		lines.push(`- Changed files: ${context.changedFiles.length}`);
	}
	lines.push("");

	if (
		context &&
		context.changedFiles.length > 0 &&
		context.changedFiles.length <= INLINE_CHANGED_FILES_LIMIT
	) {
		lines.push("### Changed Files");
		for (const file of context.changedFiles) lines.push(`- ${file}`);
		lines.push("");
	}

	if (context?.changeBrief?.trim()) {
		lines.push("### Change Brief");
		lines.push(context.changeBrief.trim());
		lines.push("");
	}
	if ((context?.changeBriefWarnings ?? []).length > 0) {
		pushBulletSection(
			lines,
			"### Change Brief Notes",
			context?.changeBriefWarnings ?? [],
		);
	}

	const consensus = buildReviewConsensus(results);
	lines.push("## Consensus");
	lines.push("");
	lines.push("### Verdict");
	lines.push(consensus.verdict);
	lines.push("");
	lines.push("### Rationale");
	lines.push(consensus.rationale);
	lines.push("");
	lines.push("### Output Quality");
	lines.push(`- Valid: ${consensus.reviewerOutputQuality.valid}`);
	lines.push(`- Partial: ${consensus.reviewerOutputQuality.partial}`);
	lines.push(`- Invalid: ${consensus.reviewerOutputQuality.invalid}`);
	lines.push(`- Failed runs: ${consensus.reviewerOutputQuality.failed}`);
	const diffOnlyFindingReviewers = results.filter((result) => {
		const findings = asStringArray(result.data?.findings);
		return findings.length > 0 && result.metadata?.repoInspectionUsed !== true;
	}).length;
	if (diffOnlyFindingReviewers > 0) {
		lines.push(
			`- Caveat: ${diffOnlyFindingReviewers} reviewer(s) reported actionable finding(s) without recorded repository inspection tool use.`,
		);
	}
	if (consensus.reviewerOutputQuality.failed > 0) {
		lines.push(
			"- Note: failed runs are also counted in the structured-format buckets above.",
		);
	}
	lines.push("");
	pushBulletSection(
		lines,
		"### Reviewer Agreement",
		consensus.reviewerAgreement,
	);
	pushBulletSection(lines, "### Findings", consensus.findings);
	pushBulletSection(
		lines,
		"### Non-blocking Callouts",
		consensus.humanReviewerCallouts,
	);
	pushBulletSection(lines, "### Suggested Follow-ups", consensus.suggestedFixQueue);

	for (let i = 0; i < results.length; i++) {
		const result = results[i]!;
		const data = result.data ?? {};
		const findings = asStringArray(data.findings);
		const suggestedNextSteps = asStringArray(data.suggestedNextSteps);
		const humanReviewerCallouts = asStringArray(data.humanReviewerCallouts);
		const verdict =
			typeof data.verdict === "string" ? data.verdict : undefined;
		const focus =
			typeof result.metadata?.focus === "string"
				? result.metadata.focus
				: undefined;
		const parseMeta = inferReviewParseMeta(result);
		const parseIssues = buildParseIssues(parseMeta);
		const rawOutput = (result.rawResponse ?? "").trim();
		const repairAttempted = result.metadata?.repairAttempted === true;
		const repairSucceeded = result.metadata?.repairSucceeded === true;
		const toolUses =
			typeof result.metadata?.toolUses === "number"
				? result.metadata.toolUses
				: undefined;
		const repoInspectionUsed = result.metadata?.repoInspectionUsed === true;
		const repoInspectionVerificationAttempted =
			result.metadata?.repoInspectionVerificationAttempted === true;
		const repoInspectionVerificationUsedTools =
			result.metadata?.repoInspectionVerificationUsedTools === true;

		lines.push(`## Reviewer ${i + 1}`);
		lines.push(`- Status: ${result.status}`);
		lines.push(`- Task ID: ${result.taskId} (${shortTaskId(result.taskId)})`);
		lines.push(`- Reviewer: ${result.label ?? result.model ?? result.task}`);
		if (result.model) lines.push(`- Model: ${result.model}`);
		if (result.thinkingLevel)
			lines.push(`- Thinking level: ${result.thinkingLevel}`);
		if (focus) lines.push(`- Focus: ${focus}`);
		lines.push(
			`- Repository inspection tools used: ${repoInspectionUsed ? "yes" : "no"}${toolUses === undefined ? "" : ` (${toolUses} tool call${toolUses === 1 ? "" : "s"})`}`,
		);
		if (repoInspectionVerificationAttempted) {
			lines.push(
				`- Repository verification retry: ${repoInspectionVerificationUsedTools ? "used tools" : "attempted; no tool use recorded"}`,
			);
		}
		if (!repoInspectionUsed && findings.length > 0) {
			lines.push(
				"- Review caveat: actionable finding(s) were reported without recorded repository inspection tool use.",
			);
		}
		if (repairAttempted)
			lines.push(
				`- Formatting repair: ${repairSucceeded ? "succeeded" : "attempted; output still partial or invalid"}`,
			);
		lines.push(`- Structured format: ${parseMeta.structure}`);
		if (parseIssues.length > 0) {
			lines.push(`- Structure issues: ${parseIssues.join("; ")}`);
		}
		lines.push("");
		lines.push("### Structured Summary");
		lines.push(result.summary || "No structured summary could be extracted.");
		lines.push("");

		lines.push("### Structured Verdict");
		lines.push(verdict ?? "Not provided.");
		lines.push("");

		pushBulletSection(lines, "### Structured Findings", findings);
		pushBulletSection(
			lines,
			"### Structured Non-blocking Callouts",
			humanReviewerCallouts,
		);
		pushBulletSection(lines, "### Structured Next Steps", suggestedNextSteps);

		if (parseMeta.structure !== "valid" && rawOutput) {
			lines.push("### Preserved Raw Output");
			lines.push(...renderTextFence(rawOutput));
			lines.push("");
		}

		if (result.error) {
			lines.push("### Error");
			lines.push(result.error);
			lines.push("");
		}
	}

	return lines.join("\n").trim();
}
