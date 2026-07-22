import * as os from "node:os";
import type {
	SubagentHistoryEntry,
	SubagentRunState,
	SubagentTaskState,
} from "./types.js";
export function workflowDisplayName(
	_workflow: SubagentRunState["workflow"],
): string {
	return "Review";
}

export function shortenPath(filePath: string): string {
	const home = os.homedir();
	return filePath.startsWith(home)
		? `~${filePath.slice(home.length)}`
		: filePath;
}

export function formatDuration(startedAt: number, endedAt?: number): string {
	const elapsed = (endedAt ?? Date.now()) - startedAt;
	if (elapsed < 1000) return `${elapsed}ms`;
	if (elapsed < 60_000) return `${(elapsed / 1000).toFixed(1)}s`;
	const minutes = Math.floor(elapsed / 60_000);
	const seconds = Math.floor((elapsed % 60_000) / 1000);
	return `${minutes}m${seconds}s`;
}

export function parseBullets(
	sectionBody: string | undefined,
): string[] | undefined {
	if (!sectionBody) return undefined;
	const items = sectionBody
		.split("\n")
		.map((line) => line.trim())
		.filter((line) => line.startsWith("- "))
		.map((line) => line.slice(2).trim())
		.filter(Boolean);
	return items.length > 0 ? items : undefined;
}

export function splitMarkdownSections(markdown: string): Map<string, string> {
	const normalized = markdown.trim();
	const sections = new Map<string, string>();
	if (!normalized) return sections;

	const sectionRegex = /^##\s+(.+)$/gm;
	const matches = [...normalized.matchAll(sectionRegex)];
	for (let i = 0; i < matches.length; i++) {
		const match = matches[i]!;
		const title = match[1]!.trim().toLowerCase();
		const start = match.index! + match[0].length;
		const end =
			i + 1 < matches.length ? matches[i + 1]!.index! : normalized.length;
		sections.set(title, normalized.slice(start, end).trim());
	}

	if (matches.length === 0) {
		sections.set("summary", normalized);
		return sections;
	}

	const preamble = normalized.slice(0, matches[0]!.index!).trim();
	if (preamble) {
		const existingSummary = sections.get("summary");
		sections.set(
			"summary",
			existingSummary ? `${preamble}\n\n${existingSummary}` : preamble,
		);
	}

	return sections;
}

export function uniqueNonEmptyStrings(items: string[]): string[] {
	return [...new Set(items.map((item) => item.trim()).filter(Boolean))];
}

export function shortTaskId(taskId: string): string {
	const match = taskId.match(/^sub_[^_]+_([a-z0-9]+)_task_(\d+)$/i);
	if (match) return `${match[1]}/${match[2]}`;
	return taskId.length > 14 ? taskId.slice(-14) : taskId;
}

function formatHistoryEntry(entry: SubagentHistoryEntry): string {
	const time = new Date(entry.timestamp).toLocaleTimeString();
	const kind = entry.kind.padEnd(11, " ");
	return `${time}  ${kind} ${entry.text}`;
}

export function renderTaskHistoryMarkdown(
	task: SubagentTaskState,
	run: SubagentRunState,
): string {
	const lines: string[] = [];
	lines.push(`# Subagent ${shortTaskId(task.taskId)}`);
	lines.push("");
	lines.push(`- Task ID: ${task.taskId}`);
	lines.push(`- Workflow: ${task.workflow}`);
	lines.push(`- Run ID: ${run.runId}`);
	lines.push(`- State: ${task.state}`);
	lines.push(`- Label: ${task.label}`);
	if (task.model) lines.push(`- Model: ${task.model}`);
	if (task.thinkingLevel)
		lines.push(`- Thinking level: ${task.thinkingLevel}`);
	if (task.cwd) lines.push(`- CWD: ${shortenPath(task.cwd)}`);
	if (task.turnCount > 0) lines.push(`- Turns: ${task.turnCount}`);
	if (task.toolUses > 0) lines.push(`- Tool uses: ${task.toolUses}`);
	if (task.tokenCount > 0) lines.push(`- Tokens: ${task.tokenCount}`);
	if (task.startedAt)
		lines.push(`- Elapsed: ${formatDuration(task.startedAt, task.endedAt)}`);
	lines.push("");
	lines.push("## Task");
	lines.push(task.task);
	lines.push("");
	if (task.summary) {
		lines.push("## Summary");
		lines.push(task.summary);
		lines.push("");
	}
	if (task.progressItems?.length) {
		lines.push("## Latest Progress");
		for (const item of task.progressItems)
			lines.push(`- [${item.done ? "x" : " "}] ${item.text}`);
		lines.push("");
	}
	lines.push("## History");
	if (task.history.length === 0) {
		lines.push("- No history recorded.");
	} else {
		for (const entry of task.history)
			lines.push(`- ${formatHistoryEntry(entry)}`);
	}
	if (task.error) {
		lines.push("");
		lines.push("## Error");
		lines.push(task.error);
	}
	return lines.join("\n").trim();
}

export function serializeRun(run: SubagentRunState) {
	return {
		workflow: run.workflow,
		runId: run.runId,
		mode: run.mode,
		state: run.state,
		startedAt: run.startedAt,
		endedAt: run.endedAt,
		tasks: run.tasks.map((task) => ({
			workflow: task.workflow,
			index: task.index,
			taskId: task.taskId,
			task: task.task,
			label: task.label,
			model: task.model,
			thinkingLevel: task.thinkingLevel,
			cwd: task.cwd,
			metadata: task.metadata,
			state: task.state,
			currentTool: task.currentTool,
			toolUses: task.toolUses,
			turnCount: task.turnCount,
			tokenCount: task.tokenCount,
			responseText: task.responseText,
			progressItems: task.progressItems ? [...task.progressItems] : undefined,
			history: task.history ? [...task.history] : [],
			recentTools: [...task.recentTools],
			recentOutputLines: [...task.recentOutputLines],
			summary: task.summary,
			data: task.data,
			parseMeta: task.parseMeta,
			error: task.error,
			startedAt: task.startedAt,
			endedAt: task.endedAt,
		})),
	};
}
