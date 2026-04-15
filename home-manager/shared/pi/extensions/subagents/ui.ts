import { Text, truncateToWidth } from "@mariozechner/pi-tui";
import {
	formatDuration,
	shortTaskId,
	workflowDisplayName,
} from "./formatting.js";
import { describeTaskExecutionProfile } from "./task-profile.js";
import type {
	SubagentProgressItem,
	SubagentRunState,
	SubagentTaskResult,
	SubagentTaskState,
} from "./types.js";

const MAX_WIDGET_LINES = 14;
const FINISHED_LINGER_MS = 6_000;
const ERROR_LINGER_MS = 12_000;

export const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

export type Theme = {
	fg(color: string, text: string): string;
	bold(text: string): string;
};

export type UICtx = {
	setStatus(key: string, text: string | undefined): void;
	setWidget(
		key: string,
		content:
			| undefined
			| ((
					tui: any,
					theme: Theme,
			  ) => { render(): string[]; invalidate(): void }),
		options?: { placement?: "aboveEditor" | "belowEditor" },
	): void;
	theme: Theme;
};

function formatTokens(count: number): string {
	if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}M token`;
	if (count >= 1_000) return `${(count / 1_000).toFixed(1)}k token`;
	return `${count} token`;
}

function formatTurns(turnCount: number): string {
	return `⟳ ${Math.max(1, turnCount)}`;
}

function truncateLine(text: string, len = 64): string {
	const line =
		text
			.split("\n")
			.find((item) => item.trim())
			?.trim() ?? "";
	if (line.length <= len) return line;
	return `${line.slice(0, len)}…`;
}

function taskLabel(
	task: Pick<SubagentTaskState | SubagentTaskResult, "label" | "task">,
): string {
	return truncateLine(task.label || task.task, 42) || "Subagent task";
}

function getCurrentProgressItem(
	progressItems: SubagentProgressItem[] | undefined,
): SubagentProgressItem | undefined {
	if (!progressItems || progressItems.length === 0) return undefined;
	return (
		progressItems.find((item) => !item.done) ??
		progressItems[progressItems.length - 1]
	);
}

function getProgressPreviewLines(
	task: SubagentTaskState,
	maxItems = 3,
): string[] {
	const items = task.progressItems;
	if (!items || items.length === 0) return [];

	const current = getCurrentProgressItem(items);
	const currentIndex = current
		? items.findIndex(
				(item) => item.text === current.text && item.done === current.done,
			)
		: -1;

	let start = 0;
	if (items.length > maxItems && currentIndex >= maxItems) {
		start = Math.max(0, Math.min(currentIndex - 1, items.length - maxItems));
	}

	const end = Math.min(items.length, start + maxItems);
	const hiddenBefore = start;
	const hiddenAfter = items.length - end;
	const visible = items.slice(start, end);

	const lines: Array<{
		text: string;
		done: boolean;
		isCurrent: boolean;
		isOverflow?: boolean;
	}> = [];
	if (hiddenBefore > 0) {
		lines.push({
			text: `+${hiddenBefore} more`,
			done: false,
			isCurrent: false,
			isOverflow: true,
		});
	}

	lines.push(
		...visible.map((item) => ({
			text: item.text,
			done: item.done,
			isCurrent: current
				? current.text === item.text && current.done === item.done
				: false,
		})),
	);

	if (hiddenAfter > 0) {
		lines.push({
			text: `+${hiddenAfter} more`,
			done: false,
			isCurrent: false,
			isOverflow: true,
		});
	}

	return lines.map((line) => {
		if (line.isOverflow) return line.text;
		return `${line.done ? "[x]" : line.isCurrent ? "[>]" : "[ ]"} ${line.text}`;
	});
}

function describeActivity(task: SubagentTaskState): string {
	const currentProgress = getCurrentProgressItem(task.progressItems);
	if (currentProgress) return currentProgress.text;

	const currentTool = task.currentTool?.trim();
	if (currentTool) {
		if (currentTool.startsWith("$ ")) return "running command…";
		if (currentTool.startsWith("read ")) return "reading…";
		if (currentTool.startsWith("grep ")) return "searching…";
		if (currentTool.startsWith("find ")) return "finding files…";
		if (currentTool.startsWith("ls ")) return "listing…";
		return `${currentTool}…`;
	}

	const responsePreview = truncateLine(task.responseText, 72);
	if (responsePreview) return responsePreview;

	const lastOutput = truncateLine(
		task.recentOutputLines[task.recentOutputLines.length - 1] ?? "",
		72,
	);
	if (lastOutput) return lastOutput;

	return "thinking…";
}

function isErrorState(state: string): boolean {
	return state === "error" || state === "aborted";
}

function shouldShowFinishedTask(task: SubagentTaskState): boolean {
	if (
		!task.endedAt ||
		(task.state !== "success" &&
			task.state !== "error" &&
			task.state !== "aborted")
	)
		return false;
	const lingerMs = isErrorState(task.state)
		? ERROR_LINGER_MS
		: FINISHED_LINGER_MS;
	return Date.now() - task.endedAt < lingerMs;
}

function renderFinishedLine(task: SubagentTaskState, theme: Theme): string {
	const duration = task.startedAt
		? formatDuration(task.startedAt, task.endedAt)
		: "";
	const workflowName = workflowDisplayName(task.workflow);
	let icon = theme.fg("success", "✓");
	let statusText = "";

	if (task.state === "error") {
		icon = theme.fg("error", "✗");
		statusText = theme.fg(
			"error",
			` error${task.error ? `: ${truncateLine(task.error, 48)}` : ""}`,
		);
	} else if (task.state === "aborted") {
		icon = theme.fg("error", "✗");
		statusText = theme.fg("warning", " aborted");
	}

	const parts: string[] = [];
	const profile = describeTaskExecutionProfile(task);
	if (profile) parts.push(profile);
	if (task.turnCount > 0) parts.push(formatTurns(task.turnCount));
	if (task.toolUses > 0)
		parts.push(`${task.toolUses} tool use${task.toolUses === 1 ? "" : "s"}`);
	if (task.tokenCount > 0) parts.push(formatTokens(task.tokenCount));
	if (duration) parts.push(duration);

	return `${icon} ${theme.fg("dim", workflowName)}  ${theme.fg("dim", taskLabel(task))} ${theme.fg("dim", "·")} ${theme.fg("dim", `id:${shortTaskId(task.taskId)}`)} ${theme.fg("dim", "·")} ${theme.fg("dim", parts.join(" · "))}${statusText}`;
}

function buildWidgetLines(
	runs: SubagentRunState[],
	frame: number,
	theme: Theme,
	width: number,
): string[] {
	const truncate = (line: string) => truncateToWidth(line, width);
	const activeTasks = runs.flatMap((run) =>
		run.tasks.filter((task) => task.state === "running"),
	);
	const pendingTasks = runs.flatMap((run) =>
		run.tasks.filter((task) => task.state === "pending"),
	);
	const finishedTasks = runs.flatMap((run) =>
		run.tasks.filter(shouldShowFinishedTask),
	);
	const hasActive = activeTasks.length > 0 || pendingTasks.length > 0;
	const hasFinished = finishedTasks.length > 0;

	if (!hasActive && !hasFinished) return [];

	const headingColor = hasActive ? "accent" : "dim";
	const headingIcon = hasActive ? "●" : "○";
	const spinner = SPINNER[frame % SPINNER.length] ?? "⠋";
	const lines: string[] = [
		truncate(
			theme.fg(headingColor, headingIcon) +
				" " +
				theme.fg(headingColor, "Subagents"),
		),
	];

	const finishedLines = finishedTasks.map((task) =>
		truncate(theme.fg("dim", "├─") + ` ${renderFinishedLine(task, theme)}`),
	);
	const runningLines = activeTasks.map((task) => {
		const stats: string[] = [];
		const workflowName = workflowDisplayName(task.workflow);
		const profile = describeTaskExecutionProfile(task);
		stats.push(formatTurns(task.turnCount));
		if (task.toolUses > 0)
			stats.push(`${task.toolUses} tool use${task.toolUses === 1 ? "" : "s"}`);
		if (task.tokenCount > 0) stats.push(formatTokens(task.tokenCount));
		if (task.startedAt) stats.push(formatDuration(task.startedAt));

		const lines = [
			truncate(
				theme.fg("dim", "├─") +
					` ${theme.fg("accent", spinner)} ${theme.bold(workflowName)}  ${theme.fg("muted", taskLabel(task))} ${theme.fg("dim", "·")} ${theme.fg("dim", `id:${shortTaskId(task.taskId)}`)} ${theme.fg("dim", "·")} ${theme.fg("dim", stats.join(" · "))}`,
			),
		];

		if (profile) {
			lines.push(
				truncate(
					theme.fg("dim", "│  ") + theme.fg("muted", `  ${profile}`),
				),
			);
		}

		const progressLines = getProgressPreviewLines(task, 3);
		if (progressLines.length > 0) {
			for (const progressLine of progressLines) {
				lines.push(
					truncate(
						theme.fg("dim", "│  ") + theme.fg("dim", `  ${progressLine}`),
					),
				);
			}
		}

		return lines;
	});

	const queuedLine =
		pendingTasks.length > 0
			? truncate(
					theme.fg("dim", "├─") +
						` ${theme.fg("muted", "◦")} ${theme.fg("dim", `${pendingTasks.length} queued`)}`,
				)
			: undefined;

	const maxBody = MAX_WIDGET_LINES - 1;
	const totalBody =
		finishedLines.length +
		runningLines.reduce((sum, lines) => sum + lines.length, 0) +
		(queuedLine ? 1 : 0);

	if (totalBody <= maxBody) {
		lines.push(...finishedLines);
		for (const taskLines of runningLines) lines.push(...taskLines);
		if (queuedLine) lines.push(queuedLine);

		if (lines.length > 1) {
			const last = lines.length - 1;
			lines[last] = lines[last]!.replace("├─", "└─");
			if (runningLines.length > 0 && !queuedLine) {
				const lastTaskLines = runningLines[runningLines.length - 1] ?? [];
				const headerIndex = last - (lastTaskLines.length - 1);
				if (headerIndex >= 1)
					lines[headerIndex] = lines[headerIndex]!.replace("├─", "└─");
				for (let i = headerIndex + 1; i <= last; i++) {
					lines[i] = lines[i]!.replace("│  ", "   ");
				}
			}
		}

		return lines;
	}

	let budget = maxBody - 1;
	let hiddenRunning = 0;
	let hiddenFinished = 0;

	for (const taskLines of runningLines) {
		if (budget >= taskLines.length) {
			lines.push(...taskLines);
			budget -= taskLines.length;
		} else {
			hiddenRunning++;
		}
	}

	if (queuedLine && budget >= 1) {
		lines.push(queuedLine);
		budget--;
	}

	for (const line of finishedLines) {
		if (budget >= 1) {
			lines.push(line);
			budget--;
		} else {
			hiddenFinished++;
		}
	}

	const overflowParts: string[] = [];
	if (hiddenRunning > 0) overflowParts.push(`${hiddenRunning} running`);
	if (hiddenFinished > 0) overflowParts.push(`${hiddenFinished} finished`);
	lines.push(
		truncate(
			theme.fg("dim", "└─") +
				` ${theme.fg("dim", `+${hiddenRunning + hiddenFinished} more (${overflowParts.join(", ")})`)}`,
		),
	);
	return lines;
}

export class SubagentWidget {
	private uiCtx: UICtx | undefined;
	private widgetFrame = 0;
	private widgetInterval: ReturnType<typeof setInterval> | undefined;
	private widgetRegistered = false;
	private tui: any | undefined;
	private lastStatusText: string | undefined;

	constructor(private getRuns: () => SubagentRunState[]) {}

	setUICtx(ctx: UICtx | undefined) {
		if (!ctx) return;
		if (ctx !== this.uiCtx) {
			this.uiCtx = ctx;
			this.widgetRegistered = false;
			this.tui = undefined;
			this.lastStatusText = undefined;
		}
	}

	private ensureTimer() {
		if (!this.widgetInterval) {
			this.widgetInterval = setInterval(() => this.update(), 80);
		}
	}

	update() {
		if (!this.uiCtx) return;
		const runs = this.getRuns();
		const activeTasks = runs.flatMap((run) =>
			run.tasks.filter((task) => task.state === "running"),
		);
		const pendingTasks = runs.flatMap((run) =>
			run.tasks.filter((task) => task.state === "pending"),
		);
		const finishedTasks = runs.flatMap((run) =>
			run.tasks.filter(shouldShowFinishedTask),
		);
		const hasAnything =
			activeTasks.length > 0 ||
			pendingTasks.length > 0 ||
			finishedTasks.length > 0;

		if (!hasAnything) {
			if (this.widgetRegistered) {
				this.uiCtx.setWidget("subagents", undefined);
				this.widgetRegistered = false;
				this.tui = undefined;
			}
			if (this.lastStatusText !== undefined) {
				this.uiCtx.setStatus("subagents", undefined);
				this.lastStatusText = undefined;
			}
			if (this.widgetInterval) {
				clearInterval(this.widgetInterval);
				this.widgetInterval = undefined;
			}
			return;
		}

		this.ensureTimer();
		this.widgetFrame++;

		let newStatusText: string | undefined;
		if (activeTasks.length > 0 || pendingTasks.length > 0) {
			const statusParts: string[] = [];
			if (activeTasks.length > 0)
				statusParts.push(`${activeTasks.length} running`);
			if (pendingTasks.length > 0)
				statusParts.push(`${pendingTasks.length} queued`);
			const total = activeTasks.length + pendingTasks.length;
			newStatusText = `${statusParts.join(", ")} subagent${total === 1 ? "" : "s"}`;
			if (activeTasks.length === 1) {
				const task = activeTasks[0]!;
				const profile = describeTaskExecutionProfile(task);
				if (profile) newStatusText += ` · ${profile}`;
				const current = describeActivity(task);
				if (current) newStatusText += ` · ${truncateLine(current, 36)}`;
			}
		}

		if (newStatusText !== this.lastStatusText) {
			this.uiCtx.setStatus("subagents", newStatusText);
			this.lastStatusText = newStatusText;
		}

		if (!this.widgetRegistered) {
			this.uiCtx.setWidget(
				"subagents",
				(tui, theme) => {
					this.tui = tui;
					return {
						render: () =>
							buildWidgetLines(
								this.getRuns(),
								this.widgetFrame,
								theme,
								tui.terminal.columns,
							),
						invalidate: () => {
							this.widgetRegistered = false;
							this.tui = undefined;
						},
					};
				},
				{ placement: "aboveEditor" },
			);
			this.widgetRegistered = true;
		} else {
			this.tui?.requestRender?.();
		}
	}

	dispose() {
		if (this.widgetInterval) {
			clearInterval(this.widgetInterval);
			this.widgetInterval = undefined;
		}
		if (this.uiCtx) {
			this.uiCtx.setWidget("subagents", undefined);
			this.uiCtx.setStatus("subagents", undefined);
		}
		this.widgetRegistered = false;
		this.tui = undefined;
		this.lastStatusText = undefined;
	}
}

export function renderSubagentTaskMessage(
	details: {
		workflow: SubagentRunState["workflow"];
		taskId: string;
		label: string;
		task: string;
	},
	expanded: boolean,
	theme: Theme,
) {
	const workflowName = workflowDisplayName(details.workflow);
	const title = `${theme.bold(workflowName)}  ${theme.fg("muted", truncateLine(details.label || details.task, 48))}`;
	const status = theme.fg("dim", `  Running (ID: ${details.taskId})`);
	if (!expanded) return new Text(`${title}\n${status}`, 0, 0);
	return new Text(
		`${title}\n${status}\n${theme.fg("dim", `  Task: ${details.task}`)}`,
		0,
		0,
	);
}
