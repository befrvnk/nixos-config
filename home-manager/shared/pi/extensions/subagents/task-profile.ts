import type { SubagentTaskResult, SubagentTaskState } from "./types.js";

function shortModelName(model: string | undefined): string | undefined {
	const normalized = model?.trim();
	if (!normalized) return undefined;
	const slash = normalized.indexOf("/");
	return slash >= 0 ? normalized.slice(slash + 1) : normalized;
}

export function describeTaskExecutionProfile(
	task: Pick<SubagentTaskState | SubagentTaskResult, "model" | "thinkingLevel">,
): string {
	const parts: string[] = [];
	const model = shortModelName(task.model);
	if (model) parts.push(model);
	if (task.thinkingLevel) parts.push(task.thinkingLevel);
	return parts.join(" · ");
}
