import type { SubagentTaskResult } from "../../types.js";

export type ReviewConsensus = {
	verdict: "correct" | "needs attention";
	findings: string[];
	humanReviewerCallouts: string[];
	suggestedFixQueue: string[];
};

function normalizeListItem(item: string): string {
	return item.trim().replace(/\s+/g, " ").toLowerCase();
}

function dedupeStable(items: string[]): string[] {
	const seen = new Set<string>();
	const deduped: string[] = [];

	for (const item of items) {
		const trimmed = item.trim();
		if (!trimmed) continue;
		const key = normalizeListItem(trimmed);
		if (seen.has(key)) continue;
		seen.add(key);
		deduped.push(trimmed);
	}

	return deduped;
}

function severityRank(finding: string): number {
	const severity = finding.match(/\[severity:\s*(high|medium|low)\]/i)?.[1]?.toLowerCase();
	if (severity === "high") return 0;
	if (severity === "medium") return 1;
	if (severity === "low") return 2;
	return 3;
}

function readStringArray(value: unknown): string[] {
	return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

export function buildReviewConsensus(
	results: SubagentTaskResult[],
): ReviewConsensus {
	const findings = dedupeStable(
		results.flatMap((result) => readStringArray(result.data?.findings)),
	)
		.map((finding, index) => ({ finding, index, rank: severityRank(finding) }))
		.sort((left, right) => left.rank - right.rank || left.index - right.index)
		.map(({ finding }) => finding);

	const humanReviewerCallouts = dedupeStable(
		results.flatMap((result) =>
			readStringArray(result.data?.humanReviewerCallouts),
		),
	);
	const suggestedFixQueue = dedupeStable(
		results.flatMap((result) =>
			readStringArray(result.data?.suggestedNextSteps),
		),
	);
	const verdictHints = results
		.map((result) => result.data?.verdict)
		.filter((value): value is string => typeof value === "string")
		.map((value) => value.toLowerCase());
	const verdict =
		findings.length > 0 || verdictHints.includes("needs attention")
			? "needs attention"
			: "correct";

	return {
		verdict,
		findings,
		humanReviewerCallouts,
		suggestedFixQueue,
	};
}
