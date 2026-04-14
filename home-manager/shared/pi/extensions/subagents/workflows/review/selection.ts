export type SmartReviewTarget =
	| "uncommitted"
	| "staged"
	| "baseBranch"
	| "commit";

export type ReviewStatusSummary = {
	hasUncommittedChanges: boolean;
	hasStagedChanges: boolean;
};

export function summarizeGitStatusForReview(
	statusShort: string,
): ReviewStatusSummary {
	let hasUncommittedChanges = false;
	let hasStagedChanges = false;

	for (const rawLine of statusShort.split("\n")) {
		const line = rawLine.trimEnd();
		if (!line.trim()) continue;
		if (line.startsWith("??")) {
			hasUncommittedChanges = true;
			continue;
		}

		const staged = line[0] && line[0] !== " " && line[0] !== "?";
		const unstaged = line[1] && line[1] !== " ";
		if (staged) hasStagedChanges = true;
		if (unstaged) hasUncommittedChanges = true;
	}

	return {
		hasUncommittedChanges,
		hasStagedChanges,
	};
}

export function chooseSmartReviewTarget(options: {
	statusShort: string;
	currentBranch?: string;
	defaultBranch?: string;
}): SmartReviewTarget {
	const status = summarizeGitStatusForReview(options.statusShort);
	if (status.hasUncommittedChanges) return "uncommitted";
	if (status.hasStagedChanges) return "staged";
	if (
		options.currentBranch?.trim() &&
		options.defaultBranch?.trim() &&
		options.currentBranch.trim() !== options.defaultBranch.trim()
	) {
		return "baseBranch";
	}
	return "commit";
}

export function rankReviewBranch(branch: string): number {
	if (branch === "main") return 0;
	if (branch === "master") return 1;
	if (branch === "origin/main") return 2;
	if (branch === "origin/master") return 3;
	return 10;
}

export function sortReviewBranches(
	branches: string[],
	currentBranch?: string,
): string[] {
	const filtered = branches.filter((branch) => branch && !branch.endsWith("/HEAD"));
	const preferredBranches = currentBranch
		? filtered.filter((branch) => branch !== currentBranch)
		: filtered;
	const source = preferredBranches.length > 0 ? preferredBranches : filtered;

	return [...source].sort(
		(a, b) => rankReviewBranch(a) - rankReviewBranch(b) || a.localeCompare(b),
	);
}
