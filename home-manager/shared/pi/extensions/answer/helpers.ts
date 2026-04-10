export interface ExtractedQuestion {
	question: string;
	context?: string;
}

export interface ExtractionResult {
	questions: ExtractedQuestion[];
}

export function buildAnswerMessage(
	questions: readonly ExtractedQuestion[],
	answers: readonly string[],
) {
	const parts: string[] = ["I answered your questions in the following way:", ""];
	for (let index = 0; index < questions.length; index += 1) {
		const question = questions[index];
		const answer = answers[index]?.trim() || "(no answer)";
		parts.push(`Q: ${question.question}`);
		if (question.context) {
			parts.push(`> ${question.context}`);
			parts.push("");
		}
		parts.push(`A: ${answer}`);
		parts.push("");
	}
	return parts.join("\n").trim();
}

export type BranchEntryLike = {
	type: string;
	message?: {
		role?: string;
		stopReason?: string;
		content?: Array<{
			type?: string;
			text?: string;
		}>;
	};
};

export function parseExtractionResult(text: string): ExtractionResult | null {
	const fencedMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
	const jsonText = (fencedMatch?.[1] ?? text).trim();

	let parsed: unknown;
	try {
		parsed = JSON.parse(jsonText);
	} catch {
		return null;
	}

	if (!parsed || typeof parsed !== "object") return null;
	const questions = (parsed as { questions?: unknown }).questions;
	if (!Array.isArray(questions)) return null;

	return {
		questions: questions.flatMap((item) => {
			if (!item || typeof item !== "object") return [];
			const question = (item as { question?: unknown }).question;
			const context = (item as { context?: unknown }).context;
			if (typeof question !== "string" || !question.trim()) return [];
			return [
				{
					question: question.trim(),
					...(typeof context === "string" && context.trim()
						? { context: context.trim() }
						: {}),
				},
			];
		}),
	};
}

export function findLastAssistantText(
	entries: readonly BranchEntryLike[],
): { text?: string; error?: string } {
	for (let index = entries.length - 1; index >= 0; index -= 1) {
		const entry = entries[index];
		if (entry.type !== "message") continue;
		const message = entry.message;
		if (message?.role !== "assistant") continue;
		if (message.stopReason !== "stop") {
			return {
				error: `Last assistant message incomplete (${message.stopReason ?? "unknown"})`,
			};
		}
		const text = (message.content ?? [])
			.filter((content): content is { type: "text"; text: string } => content.type === "text" && typeof content.text === "string")
			.map((content) => content.text)
			.join("\n")
			.trim();
		if (text) return { text };
	}

	return { error: "No assistant messages found" };
}
