export function buildReviewContextMessage(reviewMarkdown: string): string | undefined {
	const section = reviewMarkdown.trim();
	if (section.length === 0) return undefined;

	return [
		"## Additional context from /review",
		"The user previously ran the /review command. Treat the following review results from the review subagents as additional context for subsequent work in this session.",
		"",
		"Interpretation notes:",
		"- Prefer the consensus and parsed sections first.",
		"- Some reviewer outputs may be marked `partial` or `invalid`.",
		"- Partial or invalid reviewer outputs are preserved below in raw form for manual inspection.",
		"",
		section,
	].join("\n");
}
