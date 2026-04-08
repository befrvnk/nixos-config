import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Text } from "@mariozechner/pi-tui";
import { renderRunMarkdown, renderTaskHistoryMarkdown, serializeRun, shortTaskId } from "./formatting.js";
import {
  parseExploreOutput,
  renderExploreToolCall,
  renderExploreToolResult,
  renderFinalExploreResults,
} from "./explore.js";
import { EXPLORER_PROMPT } from "./explore-prompt.js";
import { REVIEWER_PROMPT } from "./review-prompt.js";
import {
  createReviewTasks,
  parseReviewOutput,
  renderFinalReviewResults,
  renderReviewToolCall,
  renderReviewToolResult,
} from "./review.js";
import {
  exploreParamsSchema,
  reviewParamsSchema,
  statusSchema,
} from "./schemas.js";
import { mapWithConcurrencyLimit, runSingleTask } from "./runner.js";
import {
  MAX_PARALLEL_TASKS,
  MAX_RECENT_RUNS,
  type ParsedSubagentOutput,
  type SubagentRunState,
  type SubagentTaskInput,
  type SubagentTaskResult,
  type SubagentWorkflow,
} from "./types.js";
import { renderSubagentTaskMessage, SubagentWidget } from "./ui.js";

const SUBAGENT_TASK_MESSAGE_TYPE = "subagent-task";
const SUBAGENT_HISTORY_MESSAGE_TYPE = "subagent-history";

function createRunId(): string {
  return `sub_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
}

function createTaskId(runId: string, index: number): string {
  return `${runId}_task_${index + 1}`;
}

function filterRuns(
  workflow: SubagentWorkflow,
  activeRuns: Map<string, SubagentRunState>,
  recentRuns: SubagentRunState[],
): SubagentRunState[] {
  return [...activeRuns.values(), ...recentRuns].filter((run) => run.workflow === workflow);
}

function getAllRuns(activeRuns: Map<string, SubagentRunState>, recentRuns: SubagentRunState[]): SubagentRunState[] {
  return [...activeRuns.values(), ...recentRuns];
}

function findTaskById(
  query: string,
  activeRuns: Map<string, SubagentRunState>,
  recentRuns: SubagentRunState[],
): { run: SubagentRunState; task: SubagentRunState["tasks"][number] } | { error: string } {
  const trimmed = query.trim();
  if (!trimmed) return { error: "Usage: /subagent <task-id>" };

  const matches = getAllRuns(activeRuns, recentRuns)
    .flatMap((run) => run.tasks.map((task) => ({ run, task })))
    .filter(({ task }) => task.taskId === trimmed || shortTaskId(task.taskId) === trimmed || task.taskId.startsWith(trimmed));

  if (matches.length === 0) return { error: `No subagent found for id: ${trimmed}` };
  if (matches.length > 1) {
    const ids = matches.slice(0, 8).map(({ task }) => shortTaskId(task.taskId)).join(", ");
    return { error: `Ambiguous subagent id: ${trimmed}. Matches: ${ids}` };
  }

  return matches[0]!;
}

export default function subagentExtension(pi: ExtensionAPI) {
  const activeRuns = new Map<string, SubagentRunState>();
  const recentRuns: SubagentRunState[] = [];
  const widget = new SubagentWidget(() => [...activeRuns.values(), ...recentRuns]);

  const rememberRun = (run: SubagentRunState) => {
    recentRuns.unshift(JSON.parse(JSON.stringify(run)) as SubagentRunState);
    if (recentRuns.length > MAX_RECENT_RUNS) recentRuns.splice(MAX_RECENT_RUNS);
  };

  const executeWorkflow = async (
    workflow: SubagentWorkflow,
    taskInputs: SubagentTaskInput[],
    options: {
      systemPrompt: string;
      parseOutput: (markdown: string) => ParsedSubagentOutput;
      onUpdate?: (update: any) => void;
      signal?: AbortSignal;
      ctx: any;
    },
  ) => {
    const runId = createRunId();
    const run: SubagentRunState = {
      workflow,
      runId,
      mode: taskInputs.length === 1 ? "single" : "parallel",
      state: "running",
      startedAt: Date.now(),
      tasks: taskInputs.map((task, index) => ({
        workflow,
        index,
        taskId: createTaskId(runId, index),
        task: task.task,
        label: task.label?.trim() || task.task.trim(),
        model: task.model,
        cwd: task.cwd,
        metadata: task.metadata,
        state: "pending",
        toolUses: 0,
        turnCount: 0,
        tokenCount: 0,
        responseText: "",
        history: [],
        recentTools: [],
        recentOutputLines: [],
      })),
    };

    const emitRunUpdate = () => {
      const serialized = serializeRun(run);
      widget.update();
      if (!options.onUpdate) return;
      options.onUpdate({
        content: [{ type: "text", text: `${workflow} run ${run.runId} in progress.` }],
        details: { workflow, run: serialized },
      });
    };

    activeRuns.set(run.runId, run);
    for (const taskState of run.tasks) {
      pi.sendMessage({
        customType: SUBAGENT_TASK_MESSAGE_TYPE,
        content: `${workflow} ${taskState.label}`,
        display: true,
        details: {
          workflow,
          taskId: taskState.taskId,
          label: taskState.label,
          task: taskState.task,
        },
      });
    }
    emitRunUpdate();

    try {
      const results = await mapWithConcurrencyLimit(run.tasks, MAX_PARALLEL_TASKS, async (taskState) =>
        runSingleTask(taskState, {
          parentCtx: options.ctx,
          emitRunUpdate,
          signal: options.signal,
          systemPrompt: options.systemPrompt,
          parseOutput: options.parseOutput,
        }),
      );

      run.endedAt = Date.now();
      run.state = results.some((result) => result.status === "error")
        ? "error"
        : results.some((result) => result.status === "aborted")
          ? "aborted"
          : "success";

      activeRuns.delete(run.runId);
      rememberRun(run);
      widget.update();
      return { run, results };
    } catch (error) {
      run.endedAt = Date.now();
      run.state = "error";
      activeRuns.delete(run.runId);
      rememberRun(run);
      widget.update();
      throw error;
    }
  };

  const executeStatus = (workflow: SubagentWorkflow, params: { action: "list" | "get"; runId?: string }) => {
    const runs = filterRuns(workflow, activeRuns, recentRuns);

    if (params.action === "list") {
      const lines: string[] = [];
      if (runs.length === 0) {
        lines.push(`No ${workflow} runs recorded in this session.`);
      } else {
        for (const run of runs) {
          lines.push(`- ${run.runId} | ${run.state} | ${run.mode} | ${run.tasks.length} task(s)`);
        }
      }
      return {
        content: [{ type: "text", text: lines.join("\n") }],
        details: { runs: runs.map(serializeRun) },
      };
    }

    if (!params.runId?.trim()) {
      return {
        content: [{ type: "text", text: 'action="get" requires runId.' }],
        isError: true,
        details: {},
      };
    }

    const run = runs.find((candidate) => candidate.runId === params.runId);
    if (!run) {
      return {
        content: [{ type: "text", text: `Run not found: ${params.runId}` }],
        isError: true,
        details: {},
      };
    }

    return {
      content: [{ type: "text", text: renderRunMarkdown(run) }],
      details: serializeRun(run),
    };
  };

  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;
    widget.setUICtx(ctx.ui);
    widget.update();
  });

  pi.on("agent_end", () => {
    widget.dispose();
  });

  pi.on("session_shutdown", () => {
    widget.dispose();
  });

  pi.registerMessageRenderer(SUBAGENT_TASK_MESSAGE_TYPE, (message, { expanded }, theme) => {
    const details = message.details as {
      workflow: SubagentWorkflow;
      taskId: string;
      label: string;
      task: string;
    } | undefined;
    if (!details) return undefined;
    return renderSubagentTaskMessage(details, expanded, theme);
  });

  pi.registerMessageRenderer(SUBAGENT_HISTORY_MESSAGE_TYPE, (message) => {
    const details = message.details as { markdown?: string } | undefined;
    if (!details?.markdown) return undefined;
    return new Text(details.markdown, 0, 0);
  });

  pi.registerCommand("subagent", {
    description: "Show detailed history for a subagent task by ID",
    handler: async (args, ctx) => {
      const result = findTaskById(args ?? "", activeRuns, recentRuns);
      if ("error" in result) {
        ctx.ui.notify(result.error, "error");
        return;
      }

      pi.sendMessage({
        customType: SUBAGENT_HISTORY_MESSAGE_TYPE,
        content: `Subagent history ${shortTaskId(result.task.taskId)}`,
        display: true,
        details: {
          markdown: renderTaskHistoryMarkdown(result.task, result.run),
        },
      });
    },
  });

  pi.registerTool({
    name: "explore",
    label: "Explore",
    description: "Run one or more isolated read-only exploration subagents and return compressed findings.",
    promptSnippet:
      "Delegate repo, docs, web, or source exploration to isolated subagents. Use this for information gathering and context compression.",
    promptGuidelines: [
      "Use this tool for exploration tasks where intermediate retrieval steps do not need to pollute the main context.",
      "Prefer parallel tasks when the information sources are independent, such as repo scan + web docs + upstream implementation lookup.",
      "Keep tasks read-only and focused on finding and summarizing information.",
      "Subagents only support GitHub Copilot models. Use the current GitHub Copilot session model or pass a GitHub Copilot model explicitly.",
      "Use the structured exploration result directly in your response instead of redoing the exploration yourself.",
      "When the tool returns multiple task results, synthesize across those results instead of discarding their structure.",
    ],
    parameters: exploreParamsSchema,
    renderCall(args, theme) {
      return renderExploreToolCall(args, theme);
    },
    renderResult(result, options, theme) {
      return renderExploreToolResult(result, options, theme);
    },
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const hasSingle = typeof params.task === "string" && params.task.trim().length > 0;
      const hasParallel = Array.isArray(params.tasks) && params.tasks.length > 0;

      if (Number(hasSingle) + Number(hasParallel) !== 1) {
        return {
          content: [{ type: "text", text: "Provide exactly one of: task or tasks." }],
          isError: true,
          details: {},
        };
      }

      const tasks: SubagentTaskInput[] = hasSingle
        ? [{
            task: params.task!.trim(),
            label: params.task!.trim(),
            model: params.model?.trim() || undefined,
            cwd: params.cwd?.trim() || ctx.cwd,
          }]
        : params.tasks!.map((task: SubagentTaskInput) => ({
            task: task.task.trim(),
            label: task.task.trim(),
            model: task.model?.trim() || undefined,
            cwd: task.cwd?.trim() || ctx.cwd,
          }));

      if (tasks.some((task) => !task.task)) {
        return {
          content: [{ type: "text", text: "All exploration tasks must be non-empty." }],
          isError: true,
          details: {},
        };
      }

      try {
        const { run, results } = await executeWorkflow("explore", tasks, {
          systemPrompt: EXPLORER_PROMPT,
          parseOutput: parseExploreOutput,
          onUpdate,
          signal,
          ctx,
        });

        return {
          content: [{ type: "text", text: renderFinalExploreResults(run.runId, run.mode, results) }],
          isError: run.state !== "success",
          details: {
            workflow: "explore",
            mode: run.mode,
            runId: run.runId,
            results,
            run: serializeRun(run),
          },
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return {
          content: [{ type: "text", text: `Explore run failed: ${message}` }],
          isError: true,
          details: {},
        };
      }
    },
  });

  pi.registerTool({
    name: "explore_status",
    label: "Explore Status",
    description: "Inspect active and recent exploration subagent runs in the current pi session.",
    promptSnippet:
      "Inspect active or recent exploration runs when you need to recall what exploration subagents are doing or what they already found.",
    parameters: statusSchema,
    async execute(_toolCallId, params) {
      return executeStatus("explore", params as { action: "list" | "get"; runId?: string });
    },
  });

  pi.registerTool({
    name: "review",
    label: "Review Changes",
    description:
      "Run one or more isolated read-only review subagents against the current git changes and return their findings.",
    promptSnippet:
      "Use multiple isolated review subagents to inspect the current git changes with different GitHub Copilot models or review focuses.",
    promptGuidelines: [
      "Use this after implementation when you want independent model opinions on the current git changes.",
      "This tool always uses the fixed default reviewers: GitHub Copilot Claude Opus 4.6 and Gemini 3.1 Pro Preview.",
      "Subagents only support GitHub Copilot models.",
      "Reviewers receive the current git diff and changed files, and may inspect those files directly for surrounding context.",
      "Synthesize reviewer findings into consensus or reviewer-specific notes instead of dumping the raw tool output unchanged.",
    ],
    parameters: reviewParamsSchema,
    renderCall(args, theme) {
      return renderReviewToolCall(args, theme);
    },
    renderResult(result, options, theme) {
      return renderReviewToolResult(result, options, theme);
    },
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      try {
        const { tasks, context } = await createReviewTasks(pi, params, ctx.cwd, signal);
        const { run, results } = await executeWorkflow("review", tasks, {
          systemPrompt: REVIEWER_PROMPT,
          parseOutput: parseReviewOutput,
          onUpdate,
          signal,
          ctx,
        });

        return {
          content: [{ type: "text", text: renderFinalReviewResults(run.runId, run.mode, results, context) }],
          isError: run.state !== "success",
          details: {
            workflow: "review",
            mode: run.mode,
            runId: run.runId,
            reviewContext: context,
            results,
            run: serializeRun(run),
          },
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return {
          content: [{ type: "text", text: `Review run failed: ${message}` }],
          isError: true,
          details: {},
        };
      }
    },
  });

  pi.registerTool({
    name: "review_status",
    label: "Review Status",
    description: "Inspect active and recent review subagent runs in the current pi session.",
    promptSnippet:
      "Inspect active or recent review runs when you need to recall what review subagents concluded.",
    parameters: statusSchema,
    async execute(_toolCallId, params) {
      return executeStatus("review", params as { action: "list" | "get"; runId?: string });
    },
  });
}
