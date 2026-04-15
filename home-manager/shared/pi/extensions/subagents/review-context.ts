export function buildReviewContextMessage(reviewMarkdown: string): string | undefined {
	const section = reviewMarkdown.trim();
	if (section.length === 0) return undefined;

	return [
		"## Additional context from /review",
		"The user previously ran the /review command. Treat the following review results from the review subagents as additional context for subsequent work in this session.",
		section,
	].join("\n\n");
}
