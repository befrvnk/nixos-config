import type {
	ParsedOutputStructure,
	SubagentTaskResult,
} from "../../types.js";

export type ReviewConsensus = {
	verdict: "correct" | "needs attention" | "inconclusive";
	findings: string[];
	humanReviewerCallouts: string[];
	suggestedFixQueue: string[];
	rationale: string;
	reviewerOutputQuality: {
		valid: number;
		partial: number;
		invalid: number;
		failed: number;
	};
	reviewerAgreement: string[];
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
	const severity = finding
		.match(/\[severity:\s*(high|medium|low)\]/i)?.[1]
		?.toLowerCase();
	if (severity === "high") return 0;
	if (severity === "medium") return 1;
	if (severity === "low") return 2;
	return 3;
}

function readStringArray(value: unknown): string[] {
	return Array.isArray(value)
		? value.filter((item): item is string => typeof item === "string")
		: [];
}

function inferStructure(result: SubagentTaskResult): ParsedOutputStructure {
	if (result.parseMeta?.structure) return result.parseMeta.structure;
	const hasStructuredFields =
		result.summary.trim().length > 0 ||
		Object.values(result.data ?? {}).some((value) => {
			if (Array.isArray(value)) return value.length > 0;
			if (typeof value === "string") return value.trim().length > 0;
			return Boolean(value);
		});
	return hasStructuredFields ? "partial" : "invalid";
}

function describeQuality(quality: ReviewConsensus["reviewerOutputQuality"]): string {
	const parts: string[] = [];
	if (quality.valid > 0) parts.push(`${quality.valid} valid`);
	if (quality.partial > 0) parts.push(`${quality.partial} partial`);
	if (quality.invalid > 0) parts.push(`${quality.invalid} invalid`);
	if (quality.failed > 0) parts.push(`${quality.failed} failed`);
	return parts.length > 0 ? parts.join(", ") : "no reviewer outputs";
}

function countNormalizedOccurrences(itemGroups: string[][]): Map<string, number> {
	const counts = new Map<string, number>();
	for (const group of itemGroups) {
		const seenInGroup = new Set<string>();
		for (const item of group) {
			const key = normalizeListItem(item);
			if (!key || seenInGroup.has(key)) continue;
			seenInGroup.add(key);
			counts.set(key, (counts.get(key) ?? 0) + 1);
		}
	}
	return counts;
}

function buildAgreementSummary(
	results: SubagentTaskResult[],
	findings: string[],
	callouts: string[],
): string[] {
	const successfulResults = results.filter((result) => result.status === "success");
	const findingCounts = countNormalizedOccurrences(
		successfulResults.map((result) => readStringArray(result.data?.findings)),
	);
	const calloutCounts = countNormalizedOccurrences(
		successfulResults.map((result) =>
			readStringArray(result.data?.humanReviewerCallouts),
		),
	);
	const sharedFindings = findings.filter(
		(finding) => (findingCounts.get(normalizeListItem(finding)) ?? 0) > 1,
	).length;
	const singleReviewerFindings = findings.length - sharedFindings;
	const sharedCallouts = callouts.filter(
		(callout) => (calloutCounts.get(normalizeListItem(callout)) ?? 0) > 1,
	).length;
	const singleReviewerCallouts = callouts.length - sharedCallouts;
	const lines: string[] = [];

	if (findings.length === 0) {
		lines.push("No actionable findings were flagged by any reviewer.");
	} else {
		if (sharedFindings > 0)
			lines.push(
				`${sharedFindings} actionable finding(s) were independently flagged by multiple reviewers.`,
			);
		if (singleReviewerFindings > 0)
			lines.push(
				`${singleReviewerFindings} actionable finding(s) were raised by only one reviewer.`,
			);
	}

	if (callouts.length === 0) {
		lines.push("No non-blocking callouts were raised.");
	} else {
		if (sharedCallouts > 0)
			lines.push(
				`${sharedCallouts} non-blocking callout(s) were shared across reviewers.`,
			);
		if (singleReviewerCallouts > 0)
			lines.push(
				`${singleReviewerCallouts} non-blocking callout(s) were raised by only one reviewer.`,
			);
	}

	return lines;
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
	const reviewerOutputQuality = results.reduce(
		(counts, result) => {
			// `failed` is an orthogonal status dimension; failed runs are still counted
			// in their inferred structured-format bucket so the renderer can report both.
			counts[inferStructure(result)] += 1;
			if (result.status !== "success") counts.failed += 1;
			return counts;
		},
		{ valid: 0, partial: 0, invalid: 0, failed: 0 },
	);
	const hasUncertainOutput =
		reviewerOutputQuality.partial > 0 ||
		reviewerOutputQuality.invalid > 0 ||
		reviewerOutputQuality.failed > 0;
	const verdict =
		findings.length > 0 || verdictHints.includes("needs attention")
			? "needs attention"
			: hasUncertainOutput || verdictHints.length === 0
				? "inconclusive"
				: "correct";
	const rationale =
		verdict === "needs attention"
			? findings.length > 0
				? `${findings.length} actionable finding(s) were parsed from reviewer output.`
				: "At least one reviewer returned a `needs attention` verdict without a structured finding."
			: verdict === "correct"
				? "All reviewer outputs were structured and no actionable findings were reported."
				: `Reviewer output quality was mixed (${describeQuality(reviewerOutputQuality)}), so the review is preserved below but the consensus is inconclusive.`;
	const reviewerAgreement = buildAgreementSummary(
		results,
		findings,
		humanReviewerCallouts,
	);

	return {
		verdict,
		findings,
		humanReviewerCallouts,
		suggestedFixQueue,
		rationale,
		reviewerOutputQuality,
		reviewerAgreement,
	};
}
