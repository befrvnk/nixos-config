export function buildReviewContextSystemPrompt(reviewMarkdowns: string[]): string | undefined {
	const sections = reviewMarkdowns
		.map((markdown) => markdown.trim())
		.filter((markdown) => markdown.length > 0);
	if (sections.length === 0) return undefined;

	const formattedSections = sections.map((markdown, index) => {
		if (sections.length === 1) return markdown;
		return `### Queued review ${index + 1}\n\n${markdown}`;
	});

	return [
		"## Additional context from /review",
		"The user previously ran the /review command. Use the following review results from the review subagents as additional context for this turn.",
		...formattedSections,
	].join("\n\n");
}
