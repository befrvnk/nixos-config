import { Text } from "@mariozechner/pi-tui";
import {
	parseBullets,
	shortTaskId,
	shortenPath,
	splitMarkdownSections,
} from "./formatting.js";
import type { ParsedSubagentOutput, SubagentTaskResult } from "./types.js";
import type { Theme } from "./ui.js";

function asStringArray(value: unknown): string[] {
	return Array.isArray(value)
		? value.filter(
				(item): item is string =>
					typeof item === "string" && item.trim().length > 0,
			)
		: [];
}

export function parseExploreOutput(markdown: string): ParsedSubagentOutput {
	const normalized = markdown.trim();
	if (!normalized) return { summary: "" };

	const sections = splitMarkdownSections(normalized);
	return {
		summary: sections.get("summary") ?? normalized,
		data: {
			sources: parseBullets(sections.get("sources")),
			keyFindings: parseBullets(sections.get("key findings")),
			suggestedNextSteps: parseBullets(sections.get("next steps")),
		},
	};
}

export function renderFinalExploreResults(
	runId: string,
	mode: "single" | "parallel",
	results: SubagentTaskResult[],
): string {
	const lines: string[] = [];

	lines.push("# Exploration Results");
	lines.push("");
	lines.push(`- Run ID: ${runId}`);
	lines.push(`- Mode: ${mode}`);
	lines.push(`- Tasks: ${results.length}`);
	lines.push("");

	for (let i = 0; i < results.length; i++) {
		const result = results[i]!;
		const sources = asStringArray(result.data?.sources);
		const keyFindings = asStringArray(result.data?.keyFindings);
		const suggestedNextSteps = asStringArray(result.data?.suggestedNextSteps);

		lines.push(`## Task ${i + 1}`);
		lines.push(`- Status: ${result.status}`);
		lines.push(`- Task ID: ${result.taskId} (${shortTaskId(result.taskId)})`);
		lines.push(`- Label: ${result.label ?? result.task}`);
		if (result.model) lines.push(`- Model: ${result.model}`);
		if (result.cwd) lines.push(`- CWD: ${shortenPath(result.cwd)}`);
		lines.push("");

		lines.push("### Summary");
		lines.push(result.summary || "No summary returned.");
		lines.push("");

		lines.push("### Sources");
		if (sources.length > 0) {
			for (const source of sources) lines.push(`- ${source}`);
		} else {
			lines.push("- None");
		}
		lines.push("");

		lines.push("### Key Findings");
		if (keyFindings.length > 0) {
			for (const finding of keyFindings) lines.push(`- ${finding}`);
		} else {
			lines.push("- None");
		}
		lines.push("");

		lines.push("### Next Steps");
		if (suggestedNextSteps.length > 0) {
			for (const step of suggestedNextSteps) lines.push(`- ${step}`);
		} else {
			lines.push("- None");
		}
		lines.push("");

		if (result.error) {
			lines.push("### Error");
			lines.push(result.error);
			lines.push("");
		}
	}

	return lines.join("\n").trim();
}

function summarizeExploreResult(result: SubagentTaskResult): string {
	const keyFindings = asStringArray(result.data?.keyFindings);
	if (keyFindings.length > 0) return keyFindings[0]!;
	if (result.summary?.trim()) return result.summary.split("\n")[0]!.trim();
	if (result.error?.trim()) return result.error.split("\n")[0]!.trim();
	return "No summary returned.";
}

function renderExploreTaskBlock(
	result: SubagentTaskResult,
	expanded: boolean,
	theme: Theme,
): string {
	const isError = result.status === "error" || result.status === "aborted";
	const icon = isError ? theme.fg("error", "✗") : theme.fg("success", "✓");
	const statusText = isError
		? theme.fg(
				result.status === "aborted" ? "warning" : "error",
				result.status === "aborted" ? "aborted" : "error",
			)
		: theme.fg("dim", "completed");
	const sources = asStringArray(result.data?.sources);
	const keyFindings = asStringArray(result.data?.keyFindings);
	const suggestedNextSteps = asStringArray(result.data?.suggestedNextSteps);
	const title = result.label?.trim() || result.task;

	let block = `${icon} ${theme.bold(title)} ${theme.fg("dim", statusText)}`;
	block += `\n  ${theme.fg("dim", `ID: ${shortTaskId(result.taskId)}`)}`;
	if (result.model) block += `\n  ${theme.fg("dim", `Model: ${result.model}`)}`;
	if (result.cwd)
		block += `\n  ${theme.fg("dim", `CWD: ${shortenPath(result.cwd)}`)}`;

	if (expanded) {
		const sections: string[] = [];
		if (result.summary) sections.push(result.summary.trim());
		sections.push(
			`Sources:\n${(sources.length > 0 ? sources : ["None"]).map((item) => `- ${item}`).join("\n")}`,
		);
		sections.push(
			`Key Findings:\n${(keyFindings.length > 0 ? keyFindings : ["None"]).map((item) => `- ${item}`).join("\n")}`,
		);
		sections.push(
			`Next Steps:\n${(suggestedNextSteps.length > 0 ? suggestedNextSteps : ["None"]).map((item) => `- ${item}`).join("\n")}`,
		);
		if (result.error) sections.push(`Error: ${result.error}`);

		for (const line of sections.join("\n\n").split("\n").slice(0, 60)) {
			block += `\n${theme.fg("dim", `  ${line}`)}`;
		}
	} else {
		block += `\n  ${theme.fg("dim", `⎿  ${summarizeExploreResult(result)}`)}`;
	}

	return block;
}

export function renderExploreToolCall(
	args: {
		task?: string;
		model?: string;
		tasks?: Array<{ task: string; model?: string }>;
	},
	theme: Theme,
) {
	const count = Array.isArray(args.tasks) ? args.tasks.length : 1;
	const firstTask = Array.isArray(args.tasks) ? args.tasks[0]?.task : args.task;
	let text = `${theme.fg("toolTitle", theme.bold("Explore"))} `;
	text += theme.fg(
		"accent",
		count > 1 ? `${count} tasks` : firstTask?.split("\n")[0]?.trim() || "task",
	);
	if (!Array.isArray(args.tasks) && args.model?.trim()) {
		text += theme.fg("muted", ` (${args.model.trim()})`);
	}
	return new Text(text, 0, 0);
}

export function renderExploreToolResult(
	result: {
		details?: unknown;
		content: Array<{ type: string; text?: string }>;
	},
	options: { expanded: boolean; isPartial: boolean },
	theme: Theme,
) {
	const details = (result.details ?? {}) as {
		run?: { tasks?: unknown[] };
		results?: SubagentTaskResult[];
	};
	const run = details.run ?? details;
	if (!run || !Array.isArray(run.tasks)) {
		const text =
			result.content[0]?.type === "text" ? (result.content[0].text ?? "") : "";
		return new Text(
			text || (options.isPartial ? "Exploring..." : "No details"),
			0,
			0,
		);
	}

	if (options.isPartial) {
		const count = Array.isArray(run.tasks) ? run.tasks.length : 0;
		const label =
			count <= 1
				? "Launching exploration subagent…"
				: `Launching ${count} exploration subagents…`;
		return new Text(theme.fg("dim", label), 0, 0);
	}

	const results = Array.isArray(details.results) ? details.results : [];
	const blocks = results.map((taskResult) =>
		renderExploreTaskBlock(taskResult, options.expanded, theme),
	);
	return new Text(blocks.join("\n\n"), 0, 0);
}
