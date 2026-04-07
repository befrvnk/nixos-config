import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import {
  renderFinalExploreResults,
  renderRunMarkdown,
  serializeRun,
} from "./formatting.js";
import { exploreParamsSchema, exploreStatusSchema } from "./schemas.js";
import { mapWithConcurrencyLimit, runSingleTask } from "./runner.js";
import {
  MAX_PARALLEL_TASKS,
  MAX_RECENT_RUNS,
  type ExploreRunState,
  type ExploreTaskInput,
} from "./types.js";
import {
  ExploreWidget,
  renderExploreTaskMessage,
  renderExploreToolCall,
  renderExploreToolResult,
} from "./ui.js";

const EXPLORE_TASK_MESSAGE_TYPE = "explore-subagent-task";

function createRunId(): string {
  return `exp_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
}

function createTaskId(runId: string, index: number): string {
  return `${runId}_task_${index + 1}`;
}

export default function exploreSubagentExtension(pi: ExtensionAPI) {
  const activeRuns = new Map<string, ExploreRunState>();
  const recentRuns: ExploreRunState[] = [];
  const widget = new ExploreWidget(() => [
    ...activeRuns.values(),
    ...recentRuns,
  ]);

  const rememberRun = (run: ExploreRunState) => {
    recentRuns.unshift(JSON.parse(JSON.stringify(run)) as ExploreRunState);
    if (recentRuns.length > MAX_RECENT_RUNS) recentRuns.splice(MAX_RECENT_RUNS);
  };

  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;
    widget.setUICtx(ctx.ui);
    widget.update();
  });

  pi.on("agent_end", () => {
    widget.dispose();
  });

  pi.registerMessageRenderer(EXPLORE_TASK_MESSAGE_TYPE, (message, { expanded }, theme) => {
    const details = message.details as {
      taskId: string;
      task: string;
    } | undefined;
    if (!details) return undefined;
    return renderExploreTaskMessage(details, expanded, theme);
  });

  pi.registerTool({
    name: "explore",
    label: "Explore",
    description:
      "Run one or more isolated read-only exploration subagents and return compressed findings.",
    promptSnippet:
      "Delegate repo, docs, web, or source exploration to isolated subagents. Use this for information gathering and context compression.",
    promptGuidelines: [
      "Use this tool for exploration tasks where intermediate retrieval steps do not need to pollute the main context.",
      "Prefer parallel tasks when the information sources are independent, such as repo scan + web docs + upstream implementation lookup.",
      "Keep tasks read-only and focused on finding and summarizing information.",
      "You may choose a model for the subagent via model on a single task or per-task model in parallel mode; if omitted, the subagent inherits the current session model.",
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
      const hasSingle =
        typeof params.task === "string" && params.task.trim().length > 0;
      const hasParallel =
        Array.isArray(params.tasks) && params.tasks.length > 0;

      if (Number(hasSingle) + Number(hasParallel) !== 1) {
        return {
          content: [
            { type: "text", text: "Provide exactly one of: task or tasks." },
          ],
          isError: true,
          details: {},
        };
      }

      const tasks: ExploreTaskInput[] = hasSingle
        ? [
            {
              task: params.task!.trim(),
              model: params.model?.trim() || undefined,
              cwd: params.cwd?.trim() || ctx.cwd,
            },
          ]
        : params.tasks!.map((task: ExploreTaskInput) => ({
            task: task.task.trim(),
            model: task.model?.trim() || undefined,
            cwd: task.cwd?.trim() || ctx.cwd,
          }));

      if (tasks.some((task) => !task.task)) {
        return {
          content: [
            { type: "text", text: "All exploration tasks must be non-empty." },
          ],
          isError: true,
          details: {},
        };
      }

      const runId = createRunId();
      const run: ExploreRunState = {
        runId,
        mode: tasks.length === 1 ? "single" : "parallel",
        state: "running",
        startedAt: Date.now(),
        tasks: tasks.map((task, index) => ({
          index,
          taskId: createTaskId(runId, index),
          task: task.task,
          model: task.model,
          cwd: task.cwd,
          state: "pending",
          toolUses: 0,
          turnCount: 0,
          tokenCount: 0,
          responseText: "",
          recentTools: [],
          recentOutputLines: [],
        })),
      };

      const emitRunUpdate = () => {
        const serialized = serializeRun(run);
        widget.update();
        if (!onUpdate) return;
        onUpdate({
          content: [{ type: "text", text: `Explore run ${run.runId} in progress.` }],
          details: { run: serialized },
        });
      };

      activeRuns.set(run.runId, run);
      for (const taskState of run.tasks) {
        pi.sendMessage({
          customType: EXPLORE_TASK_MESSAGE_TYPE,
          content: `Explore ${taskState.task}`,
          display: true,
          details: {
            taskId: taskState.taskId,
            task: taskState.task,
          },
        });
      }
      emitRunUpdate();

      try {
        const results = await mapWithConcurrencyLimit(
          run.tasks,
          MAX_PARALLEL_TASKS,
          async (taskState) => {
            return runSingleTask(taskState, ctx, emitRunUpdate, signal);
          },
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

        return {
          content: [
            {
              type: "text",
              text: renderFinalExploreResults(run.runId, run.mode, results),
            },
          ],
          isError: run.state !== "success",
          details: {
            mode: run.mode,
            runId: run.runId,
            results,
            run: serializeRun(run),
          },
        };
      } catch (error) {
        run.endedAt = Date.now();
        run.state = "error";
        activeRuns.delete(run.runId);
        rememberRun(run);
        widget.update();
        const message = error instanceof Error ? error.message : String(error);
        return {
          content: [{ type: "text", text: `Explore run failed: ${message}` }],
          isError: true,
          details: serializeRun(run),
        };
      }
    },
  });

  pi.registerTool({
    name: "explore_status",
    label: "Explore Status",
    description:
      "Inspect active and recent exploration subagent runs in the current pi session.",
    promptSnippet:
      "Inspect active or recent exploration runs when you need to recall what exploration subagents are doing or what they already found.",
    parameters: exploreStatusSchema,
    async execute(_toolCallId, params) {
      if (params.action === "list") {
        const runs = [...activeRuns.values(), ...recentRuns].map(serializeRun);
        const lines: string[] = [];
        if (runs.length === 0) {
          lines.push("No exploration runs recorded in this session.");
        } else {
          for (const run of runs) {
            lines.push(
              `- ${run.runId} | ${run.state} | ${run.mode} | ${run.tasks.length} task(s)`,
            );
          }
        }
        return {
          content: [{ type: "text", text: lines.join("\n") }],
          details: { runs },
        };
      }

      if (params.action === "get") {
        if (!params.runId?.trim()) {
          return {
            content: [{ type: "text", text: 'action="get" requires runId.' }],
            isError: true,
            details: {},
          };
        }
        const run =
          activeRuns.get(params.runId) ??
          recentRuns.find((candidate) => candidate.runId === params.runId);
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
      }

      return {
        content: [
          { type: "text", text: 'Unknown action. Use "list" or "get".' },
        ],
        isError: true,
        details: {},
      };
    },
  });
}
