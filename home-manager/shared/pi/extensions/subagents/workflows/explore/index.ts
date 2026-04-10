import { Text } from "@mariozechner/pi-tui";
import { shortTaskId, shortenPath } from "../../formatting.js";
import type { SubagentTaskResult } from "../../types.js";
import type { Theme } from "../../ui.js";
import {
	asStringArray,
	summarizeExploreResult,
} from "./results.js";
export {
	parseExploreOutput,
	renderFinalExploreResults,
} from "./results.js";

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
