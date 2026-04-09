import type { ParsedSubagentOutput } from "./types.js";

export type ProgressItem = {
	text: string;
	done: boolean;
};

const OPEN_MARKER = "[[progress]]";
const CLOSE_MARKER = "[[/progress]]";

export function parseProgressItems(block: string): ProgressItem[] {
	return block
		.split("\n")
		.map((line) => line.trim())
		.map((line) => {
			const match = line.match(/^- \[(x| )\]\s+(.+)$/i);
			if (!match) return undefined;
			return {
				done: match[1]!.toLowerCase() === "x",
				text: match[2]!.trim(),
			} satisfies ProgressItem;
		})
		.filter((item): item is ProgressItem => Boolean(item?.text));
}

export function extractLatestProgress(
	text: string,
): ProgressItem[] | undefined {
	if (!text) return undefined;
	let searchIndex = 0;
	let latest: string | undefined;

	while (true) {
		const open = text.indexOf(OPEN_MARKER, searchIndex);
		if (open === -1) break;
		const close = text.indexOf(CLOSE_MARKER, open + OPEN_MARKER.length);
		if (close === -1) break;
		latest = text.slice(open + OPEN_MARKER.length, close).trim();
		searchIndex = close + CLOSE_MARKER.length;
	}

	if (!latest) return undefined;
	const items = parseProgressItems(latest);
	return items.length > 0 ? items : undefined;
}

export function stripProgressBlocks(text: string): string {
	if (!text) return text;
	return text
		.replace(/\[\[progress\]\][\s\S]*?\[\[\/progress\]\]\s*/g, "")
		.trim();
}

export function cleanParsedOutput(
	output: ParsedSubagentOutput,
): ParsedSubagentOutput {
	return {
		summary: stripProgressBlocks(output.summary),
		data: output.data,
	};
}
