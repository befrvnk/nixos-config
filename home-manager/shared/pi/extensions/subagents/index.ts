import type {
	ExtensionAPI,
	ExtensionCommandContext,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import {
	BorderedLoader,
	getMarkdownTheme,
} from "@mariozechner/pi-coding-agent";
import { Markdown, Text } from "@mariozechner/pi-tui";
import {
	parseExploreOutput,
	renderExploreToolCall,
	renderExploreToolResult,
	renderFinalExploreResults,
} from "./workflows/explore/index.js";
import { EXPLORER_PROMPT } from "./workflows/explore/prompt.js";
import {
	renderRunMarkdown,
	renderTaskHistoryMarkdown,
	serializeRun,
	shortTaskId,
	uniqueNonEmptyStrings,
} from "./formatting.js";
import {
	filterRuns,
	findTaskById,
	parseReviewCommandArgs,
	REVIEW_COMMAND_USAGE,
	type ReviewSelection,
} from "./commands.js";
import {
	DEFAULT_EXPLORE_MODEL,
	DEFAULT_EXPLORE_THINKING_LEVEL,
} from "./model-policy.js";
import {
	createReviewTasks,
	parseReviewOutput,
	renderFinalReviewResults,
} from "./workflows/review/index.js";
import { buildReviewContextSystemPrompt } from "./review-context.js";
import { REVIEWER_PROMPT } from "./workflows/review/prompt.js";
import { mapWithConcurrencyLimit, runSingleTask } from "./runner.js";
import {
	exploreParamsSchema,
	statusSchema,
} from "./workflows/explore/schema.js";
import {
	MAX_PARALLEL_TASKS,
	MAX_RECENT_RUNS,
	type ParsedSubagentOutput,
	type SubagentRunState,
	type SubagentTaskInput,
	type SubagentWorkflow,
} from "./types.js";
import { renderSubagentTaskMessage, SubagentWidget } from "./ui.js";

const SUBAGENT_TASK_MESSAGE_TYPE = "subagent-task";
const SUBAGENT_MARKDOWN_MESSAGE_TYPE = "subagent-markdown";
const MARKDOWN_PREVIEW_LINES = 8;

function renderMarkdownPreview(markdown: string, theme: { fg(color: string, text: string): string }) {
	const lines = markdown.trim().split("\n");
	const preview = lines.slice(0, MARKDOWN_PREVIEW_LINES).join("\n").trim();
	if (lines.length <= MARKDOWN_PREVIEW_LINES) return preview;
	return `${preview}\n${theme.fg("muted", "(expand to view full formatted markdown)")}`;
}

type ReviewExecutionResult =
	| { status: "success" }
	| { status: "aborted" }
	| { status: "partial"; message: string }
	| { status: "error"; message: string };

function createRunId(): string {
	return `sub_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
}

function createTaskId(runId: string, index: number): string {
	return `${runId}_task_${index + 1}`;
}

async function listReviewBranches(
	pi: ExtensionAPI,
	cwd: string,
): Promise<string[]> {
	const [refsResult, currentBranchResult] = await Promise.all([
		pi.exec(
			"git",
			[
				"for-each-ref",
				"--format=%(refname:short)",
				"refs/heads",
				"refs/remotes",
			],
			{ cwd },
		),
		pi.exec("git", ["branch", "--show-current"], { cwd }),
	]);

	if ((refsResult.code ?? 1) !== 0) {
		throw new Error(
			refsResult.stderr?.trim() ||
				refsResult.stdout?.trim() ||
				"Failed to list git branches.",
		);
	}

	const currentBranch = currentBranchResult.stdout?.trim() ?? "";
	const allBranches = uniqueNonEmptyStrings(
		(refsResult.stdout ?? "").split("\n"),
	).filter((branch) => !branch.endsWith("/HEAD"));
	const preferredBranches = allBranches.filter(
		(branch) => branch !== currentBranch,
	);
	const branches =
		preferredBranches.length > 0 ? preferredBranches : allBranches;

	const priority = (branch: string): number => {
		if (branch === "main") return 0;
		if (branch === "master") return 1;
		if (branch === "origin/main") return 2;
		if (branch === "origin/master") return 3;
		return 10;
	};

	return [...branches].sort(
		(a, b) => priority(a) - priority(b) || a.localeCompare(b),
	);
}

async function promptForReviewSelection(
	pi: ExtensionAPI,
	ctx: ExtensionCommandContext,
): Promise<ReviewSelection | undefined> {
	if (!ctx.hasUI) return undefined;

	const choice = await ctx.ui.select("Select review target", [
		"Review uncommitted changes",
		"Review staged changes",
		"Review against a base branch",
	]);
	if (!choice) return undefined;

	if (choice === "Review uncommitted changes") {
		return {
			label: "uncommitted changes",
			request: { target: { type: "uncommitted" } },
		};
	}

	if (choice === "Review staged changes") {
		return {
			label: "staged changes",
			request: { target: { type: "staged" } },
		};
	}

	const branches = await listReviewBranches(pi, ctx.cwd);
	if (branches.length === 0) {
		ctx.ui.notify("No branches available for base-branch review.", "warning");
		return undefined;
	}

	const branch = await ctx.ui.select("Select base branch", branches);
	if (!branch) return undefined;

	return {
		label: `base branch ${branch}`,
		request: { target: { type: "baseBranch", branch } },
	};
}

function showCommandMessage(
	pi: ExtensionAPI,
	markdown: string,
	content: string,
) {
	pi.sendMessage({
		customType: SUBAGENT_MARKDOWN_MESSAGE_TYPE,
		content,
		display: true,
		details: { markdown },
	});
}

export default function subagentExtension(pi: ExtensionAPI) {
	const activeRuns = new Map<string, SubagentRunState>();
	const recentRuns: SubagentRunState[] = [];
	const pendingReviewContexts: string[] = [];
	const widget = new SubagentWidget(() => [
		...activeRuns.values(),
		...recentRuns,
	]);

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
			onUpdate?: (update: unknown) => void;
			signal?: AbortSignal;
			ctx: ExtensionContext | ExtensionCommandContext;
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
				thinkingLevel: task.thinkingLevel,
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
				content: [
					{ type: "text", text: `${workflow} run ${run.runId} in progress.` },
				],
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
			const results = await mapWithConcurrencyLimit(
				run.tasks,
				MAX_PARALLEL_TASKS,
				async (taskState) =>
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

	const executeStatus = (
		workflow: SubagentWorkflow,
		params: { action: "list" | "get"; runId?: string },
	) => {
		const runs = filterRuns(workflow, activeRuns, recentRuns);

		if (params.action === "list") {
			const lines: string[] = [];
			if (runs.length === 0) {
				lines.push(`No ${workflow} runs recorded in this session.`);
			} else {
				for (const run of runs) {
					lines.push(
						`- ${run.runId} | ${run.state} | ${run.mode} | ${run.tasks.length} task(s)`,
					);
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

	const runReviewSelection = async (
		selection: ReviewSelection,
		ctx: ExtensionCommandContext,
		signal?: AbortSignal,
	): Promise<ReviewExecutionResult> => {
		try {
			const { tasks, context } = await createReviewTasks(
				pi,
				selection.request,
				ctx.cwd,
				signal,
			);
			const { run, results } = await executeWorkflow("review", tasks, {
				systemPrompt: REVIEWER_PROMPT,
				parseOutput: parseReviewOutput,
				signal,
				ctx,
			});

			if (signal?.aborted || run.state === "aborted") {
				return { status: "aborted" };
			}

			const reviewMarkdown = renderFinalReviewResults(
				run.runId,
				run.mode,
				results,
				context,
			);
			showCommandMessage(
				pi,
				reviewMarkdown,
				`Review ${selection.label}`,
			);
			pendingReviewContexts.push(reviewMarkdown);

			if (run.state === "success") {
				return { status: "success" };
			}

			return {
				status: "partial",
				message: `Review completed with ${run.state} state for ${selection.label}.`,
			};
		} catch (error) {
			if (signal?.aborted) return { status: "aborted" };
			return {
				status: "error",
				message: error instanceof Error ? error.message : String(error),
			};
		}
	};

	const executeReviewCommand = async (
		args: string | undefined,
		ctx: ExtensionCommandContext,
	) => {
		await ctx.waitForIdle();

		const parsed = parseReviewCommandArgs(args);
		if (parsed && "error" in parsed) {
			if (ctx.hasUI) ctx.ui.notify(parsed.error, "error");
			else showCommandMessage(pi, parsed.error, "Review command usage");
			return;
		}

		if (!parsed && !ctx.hasUI) {
			showCommandMessage(pi, REVIEW_COMMAND_USAGE, "Review command usage");
			return;
		}

		const selection = parsed ?? (await promptForReviewSelection(pi, ctx));
		if (!selection) return;

		let result: ReviewExecutionResult;
		if (ctx.hasUI) {
			result = await ctx.ui.custom<ReviewExecutionResult>(
				(tui, theme, _kb, done) => {
					const loader = new BorderedLoader(
						tui,
						theme,
						`Running review for ${selection.label}...`,
					);
					let settled = false;
					const finish = (value: ReviewExecutionResult) => {
						if (settled) return;
						settled = true;
						done(value);
					};

					loader.onAbort = () => finish({ status: "aborted" });
					void runReviewSelection(selection, ctx, loader.signal).then(finish);
					return loader;
				},
			);
		} else {
			result = await runReviewSelection(selection, ctx);
		}

		if (!ctx.hasUI) {
			if (result.status === "error") {
				showCommandMessage(
					pi,
					`Review failed: ${result.message}`,
					"Review failed",
				);
			}
			return;
		}

		switch (result.status) {
			case "success":
				ctx.ui.notify(
					`Review finished for ${selection.label}. Findings will be added to the next agent turn.`,
					"info",
				);
				return;
			case "aborted":
				ctx.ui.notify(`Review cancelled for ${selection.label}.`, "info");
				return;
			case "partial":
				ctx.ui.notify(
					`${result.message} Findings will be added to the next agent turn.`,
					"warning",
				);
				return;
			case "error":
				ctx.ui.notify(`Review failed: ${result.message}`, "error");
				return;
		}
	};

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;
		widget.setUICtx(ctx.ui);
		widget.update();
	});

	pi.on("before_agent_start", (event) => {
		const reviewContext = buildReviewContextSystemPrompt(
			pendingReviewContexts,
		);
		if (!reviewContext) return undefined;

		pendingReviewContexts.length = 0;
		return {
			systemPrompt: `${event.systemPrompt}\n\n${reviewContext}`,
		};
	});

	pi.on("agent_end", () => {
		widget.dispose();
	});

	pi.on("session_shutdown", () => {
		widget.dispose();
	});

	pi.registerMessageRenderer(
		SUBAGENT_TASK_MESSAGE_TYPE,
		(message, { expanded }, theme) => {
			const details = message.details as
				| {
						workflow: SubagentWorkflow;
						taskId: string;
						label: string;
						task: string;
				  }
				| undefined;
			if (!details) return undefined;
			return renderSubagentTaskMessage(details, expanded, theme);
		},
	);

	pi.registerMessageRenderer(
		SUBAGENT_MARKDOWN_MESSAGE_TYPE,
		(message, { expanded }, theme) => {
			const details = message.details as { markdown?: string } | undefined;
			if (!details?.markdown) return undefined;
			if (!expanded) {
				return new Text(renderMarkdownPreview(details.markdown, theme), 0, 0);
			}
			return new Markdown(details.markdown, 0, 0, getMarkdownTheme());
		},
	);

	pi.registerCommand("subagent", {
		description: "Show detailed history for a subagent task by ID",
		handler: async (args, ctx) => {
			const result = findTaskById(args ?? "", activeRuns, recentRuns);
			if ("error" in result) {
				ctx.ui.notify(result.error, "error");
				return;
			}

			showCommandMessage(
				pi,
				renderTaskHistoryMarkdown(result.task, result.run),
				`Subagent history ${shortTaskId(result.task.taskId)}`,
			);
		},
	});

	pi.registerCommand("review", {
		description:
			"Run the fixed review pair against uncommitted changes, staged changes, or a base branch",
		handler: async (args, ctx) => {
			await executeReviewCommand(args, ctx);
		},
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
			"Subagents only support GitHub Copilot models. Choose one of the allowed explore models per task.",
			"Use cheaper models for lightweight scans and stronger models when synthesis is more important.",
			"Use multiple tasks when the work is naturally parallel.",
			"Do not use explore for formal audits or code review; /review is user-triggered.",
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

			if (hasParallel && typeof params.model === "string") {
				return {
					content: [
						{
							type: "text",
							text: 'Top-level model is only valid when using the single-task "task" form.',
						},
					],
					isError: true,
					details: {},
				};
			}

			const tasks: SubagentTaskInput[] = hasSingle
				? (() => {
						const taskText = params.task?.trim() ?? "";
						return [
							{
								task: taskText,
								label: taskText,
								model: params.model?.trim() || DEFAULT_EXPLORE_MODEL,
								thinkingLevel: DEFAULT_EXPLORE_THINKING_LEVEL,
								cwd: params.cwd?.trim() || ctx.cwd,
							},
						];
					})()
				: (params.tasks ?? []).map((task: SubagentTaskInput) => ({
						task: task.task.trim(),
						label: task.task.trim(),
						model: task.model?.trim() || DEFAULT_EXPLORE_MODEL,
						thinkingLevel: DEFAULT_EXPLORE_THINKING_LEVEL,
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

			try {
				const { run, results } = await executeWorkflow("explore", tasks, {
					systemPrompt: EXPLORER_PROMPT,
					parseOutput: parseExploreOutput,
					onUpdate,
					signal,
					ctx,
				});

				return {
					content: [
						{
							type: "text",
							text: renderFinalExploreResults(run.runId, run.mode, results),
						},
					],
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
		description:
			"Inspect active and recent exploration subagent runs in the current pi session.",
		promptSnippet:
			"Inspect active or recent exploration runs when you need to recall what exploration subagents are doing or what they already found.",
		parameters: statusSchema,
		async execute(_toolCallId, params) {
			return executeStatus(
				"explore",
				params as { action: "list" | "get"; runId?: string },
			);
		},
	});
}
