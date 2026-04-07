export const EXPLORATION_TOOLS = ["read", "grep", "find", "ls", "bash"] as const;
export const MAX_PARALLEL_TASKS = 4;
export const MAX_RECENT_RUNS = 10;
export const MAX_RECENT_TOOLS = 6;
export const MAX_RECENT_OUTPUT_LINES = 8;

export type ExploreTaskInput = {
  task: string;
  model?: string;
  cwd?: string;
};

export type ExploreTaskResult = {
  task: string;
  model?: string;
  cwd?: string;
  status: "success" | "error" | "aborted";
  summary: string;
  sources?: string[];
  keyFindings?: string[];
  suggestedNextSteps?: string[];
  error?: string;
};

export type ExploreTaskState = {
  index: number;
  taskId: string;
  task: string;
  model?: string;
  cwd?: string;
  state: "pending" | "running" | "success" | "error" | "aborted";
  currentTool?: string;
  toolUses: number;
  turnCount: number;
  tokenCount: number;
  responseText: string;
  recentTools: string[];
  recentOutputLines: string[];
  summary?: string;
  sources?: string[];
  keyFindings?: string[];
  suggestedNextSteps?: string[];
  error?: string;
  startedAt?: number;
  endedAt?: number;
};

export type ExploreRunState = {
  runId: string;
  mode: "single" | "parallel";
  state: "running" | "success" | "error" | "aborted";
  startedAt: number;
  endedAt?: number;
  tasks: ExploreTaskState[];
};
