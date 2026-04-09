export const COPILOT_PROVIDER = "github-copilot";
export const SUBAGENT_TOOLS = ["read", "grep", "find", "ls", "bash"] as const;
export const MAX_PARALLEL_TASKS = 4;
export const MAX_LOGICAL_EXPLORE_TASKS = 8;
export const MAX_RECENT_RUNS = 10;
export const MAX_RECENT_TOOLS = 6;
export const MAX_RECENT_OUTPUT_LINES = 8;
export const MAX_HISTORY_ITEMS = 120;

export type SubagentWorkflow = "explore" | "review";
export type SubagentThinkingLevel =
	| "off"
	| "minimal"
	| "low"
	| "medium"
	| "high"
	| "xhigh";
export type SubagentRunMode = "single" | "parallel";
export type SubagentTaskStatus = "success" | "error" | "aborted";
export type SubagentRunStatus = "running" | SubagentTaskStatus;

export type SubagentTaskInput = {
	task: string;
	label?: string;
	model?: string;
	thinkingLevel?: SubagentThinkingLevel;
	cwd?: string;
	metadata?: Record<string, unknown>;
};

export type SubagentProgressItem = {
	text: string;
	done: boolean;
};

export type SubagentHistoryEntry = {
	timestamp: number;
	kind:
		| "lifecycle"
		| "progress"
		| "tool"
		| "tool_result"
		| "assistant"
		| "error";
	text: string;
};

export type ParsedSubagentOutput = {
	summary: string;
	data?: Record<string, unknown>;
};

export type SubagentTaskResult = {
	taskId: string;
	task: string;
	label?: string;
	model?: string;
	thinkingLevel?: SubagentThinkingLevel;
	cwd?: string;
	status: SubagentTaskStatus;
	summary: string;
	data?: Record<string, unknown>;
	error?: string;
	rawResponse?: string;
	metadata?: Record<string, unknown>;
};

export type SubagentTaskState = {
	workflow: SubagentWorkflow;
	index: number;
	taskId: string;
	task: string;
	label: string;
	model?: string;
	thinkingLevel?: SubagentThinkingLevel;
	cwd?: string;
	metadata?: Record<string, unknown>;
	state: "pending" | "running" | SubagentTaskStatus;
	currentTool?: string;
	toolUses: number;
	turnCount: number;
	tokenCount: number;
	responseText: string;
	progressItems?: SubagentProgressItem[];
	history: SubagentHistoryEntry[];
	recentTools: string[];
	recentOutputLines: string[];
	summary?: string;
	data?: Record<string, unknown>;
	error?: string;
	startedAt?: number;
	endedAt?: number;
};

export type SubagentRunState = {
	workflow: SubagentWorkflow;
	runId: string;
	mode: SubagentRunMode;
	state: SubagentRunStatus;
	startedAt: number;
	endedAt?: number;
	tasks: SubagentTaskState[];
};
