import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import {
  BorderedLoader,
  DynamicBorder,
  getMarkdownTheme,
} from "@earendil-works/pi-coding-agent";
import {
  Container,
  fuzzyFilter,
  Input,
  Markdown,
  type SelectItem,
  SelectList,
  Spacer,
  Text,
  truncateToWidth,
} from "@earendil-works/pi-tui";
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
  uniqueNonEmptyStrings,
} from "./formatting.js";
import {
  filterRuns,
  findTaskById,
  parseReviewCommandArgs,
  REVIEW_COMMAND_USAGE,
  type ReviewSelection,
} from "./commands.js";
import { buildExploreTaskInputs, findRunOrThrow } from "./tool-validation.js";
import {
  buildReviewRepairPrompt,
  createReviewBriefTask,
  createReviewContext,
  createReviewTasksForContext,
  parseReviewBriefOutput,
  parseReviewOutput,
  renderFinalReviewResults,
  withReviewChangeBrief,
} from "./workflows/review/index.js";
import { buildReviewContextMessage } from "./review-context.js";
import {
  REVIEW_BRIEF_PROMPT,
  REVIEWER_PROMPT,
} from "./workflows/review/prompt.js";
import {
  chooseSmartReviewTarget,
  sortReviewBranches,
} from "./workflows/review/selection.js";
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
  type SubagentTaskState,
  type SubagentWorkflow,
} from "./types.js";
import { renderSubagentTaskMessage, SubagentWidget } from "./ui.js";
import {
  createExploreCacheMetadata,
  createExplorationKey,
  EXPLORE_CACHE_ENTRY_TYPE,
  findReusableExploration,
  hashWorkspaceRevision,
  MAX_ACTIVE_EXPLORE_RUNS,
  MAX_EXPLORE_SESSION_TOKENS,
  parseFreshExploreArgs,
  rememberExploration,
  restoreExploreCacheState,
  subscribeToActiveExploration,
  type ActiveExploration,
  type ExploreCacheRecord,
  WORKSPACE_GENERATION_ENTRY_TYPE,
} from "./explore-cache.js";

const SUBAGENT_TASK_ENTRY_TYPE = "subagent-task";
const SUBAGENT_MARKDOWN_ENTRY_TYPE = "subagent-markdown";
const SUBAGENT_REVIEW_MESSAGE_TYPE = "subagent-review";
const SUBAGENT_EXPLORE_MESSAGE_TYPE = "subagent-explore";
const MARKDOWN_PREVIEW_LINES = 8;

function renderMarkdownPreview(
  markdown: string,
  theme: { fg(color: string, text: string): string },
) {
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

type ReviewCommitSelection = {
  sha: string;
  title: string;
  label: string;
};

type ReviewTargetChoice = "uncommitted" | "staged" | "baseBranch" | "commit";

async function getCurrentBranch(
  pi: ExtensionAPI,
  cwd: string,
): Promise<string | undefined> {
  const result = await pi.exec("git", ["branch", "--show-current"], { cwd });
  if ((result.code ?? 1) !== 0) return undefined;
  return result.stdout?.trim() || undefined;
}

async function listAllReviewBranches(
  pi: ExtensionAPI,
  cwd: string,
): Promise<string[]> {
  const refsResult = await pi.exec(
    "git",
    ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"],
    { cwd },
  );

  if ((refsResult.code ?? 1) !== 0) {
    throw new Error(
      refsResult.stderr?.trim() ||
        refsResult.stdout?.trim() ||
        "Failed to list git branches.",
    );
  }

  return uniqueNonEmptyStrings((refsResult.stdout ?? "").split("\n"));
}

async function getDefaultBranch(
  pi: ExtensionAPI,
  cwd: string,
): Promise<string | undefined> {
  const remoteHeadResult = await pi.exec(
    "git",
    ["symbolic-ref", "refs/remotes/origin/HEAD", "--short"],
    { cwd },
  );
  if ((remoteHeadResult.code ?? 1) === 0) {
    const remoteHead = remoteHeadResult.stdout?.trim();
    if (remoteHead?.startsWith("origin/")) {
      return remoteHead.slice("origin/".length);
    }
  }

  const branches = await listAllReviewBranches(pi, cwd);
  for (const branch of ["main", "master", "origin/main", "origin/master"]) {
    if (branches.includes(branch)) {
      return branch.startsWith("origin/")
        ? branch.slice("origin/".length)
        : branch;
    }
  }
  return undefined;
}

async function getReviewStatusShort(
  pi: ExtensionAPI,
  cwd: string,
): Promise<string> {
  const result = await pi.exec(
    "git",
    ["status", "--short", "--untracked-files=all"],
    {
      cwd,
    },
  );
  if ((result.code ?? 1) !== 0) {
    throw new Error(
      result.stderr?.trim() ||
        result.stdout?.trim() ||
        "Failed to inspect git status for review defaults.",
    );
  }
  return result.stdout ?? "";
}

async function listReviewBranches(
  pi: ExtensionAPI,
  cwd: string,
): Promise<string[]> {
  const [branches, currentBranch] = await Promise.all([
    listAllReviewBranches(pi, cwd),
    getCurrentBranch(pi, cwd),
  ]);
  return sortReviewBranches(branches, currentBranch);
}

async function listReviewCommits(
  pi: ExtensionAPI,
  cwd: string,
): Promise<ReviewCommitSelection[]> {
  const result = await pi.exec(
    "git",
    ["log", "--format=%H%x09%s", "-n", "20"],
    { cwd },
  );
  if ((result.code ?? 1) !== 0) {
    throw new Error(
      result.stderr?.trim() ||
        result.stdout?.trim() ||
        "Failed to list recent commits.",
    );
  }

  return uniqueNonEmptyStrings((result.stdout ?? "").split("\n")).map(
    (line) => {
      const [sha = "", title = ""] = line.split("\t");
      const trimmedSha = sha.trim();
      const trimmedTitle = title.trim();
      return {
        sha: trimmedSha,
        title: trimmedTitle,
        label: trimmedTitle
          ? `${trimmedSha.slice(0, 12)} ${trimmedTitle}`
          : trimmedSha,
      };
    },
  );
}

async function showSelectableList(
  ctx: ExtensionCommandContext,
  options: {
    title: string;
    items: SelectItem[];
    filterPrompt?: string;
    helpText: string;
    selectedIndex?: number;
  },
): Promise<string | undefined> {
  if (ctx.mode === "rpc") {
    const labels = options.items.map((item, index) =>
      `${item.label}${item.description ? ` — ${item.description}` : ""} [${index + 1}]`
    );
    const selected = await ctx.ui.select(options.title, labels);
    const index = selected ? labels.indexOf(selected) : -1;
    return index >= 0 ? String(options.items[index]!.value) : undefined;
  }
  if (ctx.mode !== "tui") return undefined;

  return ctx.ui.custom<string | undefined>((tui, theme, keybindings, done) => {
    const container = new Container();
    container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));
    container.addChild(new Text(theme.fg("accent", theme.bold(options.title))));

    const searchInput = new Input();
    const hasFilter = Boolean(options.filterPrompt);
    if (hasFilter) {
      container.addChild(
        new Text(theme.fg("muted", options.filterPrompt ?? "Filter")),
      );
      container.addChild(searchInput);
      container.addChild(new Spacer(1));
    }

    const listContainer = new Container();
    container.addChild(listContainer);
    container.addChild(new Text(theme.fg("dim", options.helpText)));
    container.addChild(new DynamicBorder((text) => theme.fg("accent", text)));

    let filteredItems = options.items;
    let selectList: SelectList | null = null;

    const updateList = () => {
      listContainer.clear();
      if (filteredItems.length === 0) {
        listContainer.addChild(
          new Text(theme.fg("warning", "  No matching items")),
        );
        selectList = null;
        return;
      }

      selectList = new SelectList(
        filteredItems,
        Math.min(filteredItems.length, 10),
        {
          selectedPrefix: (text) => theme.fg("accent", text),
          selectedText: (text) => theme.fg("accent", text),
          description: (text) => theme.fg("muted", text),
          scrollInfo: (text) => theme.fg("dim", text),
          noMatch: (text) => theme.fg("warning", text),
        },
      );
      if (typeof options.selectedIndex === "number") {
        selectList.setSelectedIndex(
          Math.max(
            0,
            Math.min(options.selectedIndex, filteredItems.length - 1),
          ),
        );
      }
      selectList.onSelect = (item) => done(String(item.value));
      selectList.onCancel = () => done(undefined);
      listContainer.addChild(selectList);
    };

    const applyFilter = () => {
      if (!hasFilter) {
        filteredItems = options.items;
        updateList();
        return;
      }
      const query = searchInput.getValue();
      filteredItems = query
        ? fuzzyFilter(
            options.items,
            query,
            (item) => `${item.label} ${item.value} ${item.description ?? ""}`,
          )
        : options.items;
      updateList();
    };

    applyFilter();

    return {
      get focused() {
        return searchInput.focused;
      },
      set focused(value: boolean) {
        searchInput.focused = value;
      },
      render(width: number) {
        return container.render(width).map((line) => truncateToWidth(line, Math.max(0, width), ""));
      },
      invalidate() {
        container.invalidate();
        searchInput.invalidate();
      },
      handleInput(data: string) {
        if (
          keybindings.matches(data, "tui.select.up") ||
          keybindings.matches(data, "tui.select.down") ||
          keybindings.matches(data, "tui.select.confirm") ||
          keybindings.matches(data, "tui.select.cancel")
        ) {
          if (selectList) {
            selectList.handleInput(data);
          } else if (keybindings.matches(data, "tui.select.cancel")) {
            done(undefined);
          }
          tui.requestRender();
          return;
        }

        if (hasFilter) {
          searchInput.handleInput(data);
          applyFilter();
          tui.requestRender();
        }
      },
    };
  });
}

async function promptForOptionalReviewInstructions(
  ctx: ExtensionCommandContext,
  selection: ReviewSelection,
): Promise<ReviewSelection> {
  const choice = await ctx.ui.select("Add extra review instructions?", [
    "Skip",
    "Add instructions",
  ]);
  if (choice !== "Add instructions") return selection;

  const value = await ctx.ui.editor(
    "Enter additional review instructions:",
    "",
  );
  const prompt = value?.trim();
  if (!prompt) return selection;
  return {
    ...selection,
    request: {
      ...selection.request,
      prompt,
    },
  };
}

async function promptForReviewSelection(
  pi: ExtensionAPI,
  ctx: ExtensionCommandContext,
): Promise<ReviewSelection | undefined> {
  if (ctx.mode !== "tui" && ctx.mode !== "rpc") return undefined;

  const [statusShort, currentBranch, defaultBranch] = await Promise.all([
    getReviewStatusShort(pi, ctx.cwd),
    getCurrentBranch(pi, ctx.cwd),
    getDefaultBranch(pi, ctx.cwd),
  ]);
  const smartDefault = chooseSmartReviewTarget({
    statusShort,
    currentBranch,
    defaultBranch,
  });
  const targetItems: Array<SelectItem & { value: ReviewTargetChoice }> = [
    {
      value: "uncommitted",
      label: "Review uncommitted changes",
      description: "unstaged and untracked files",
    },
    {
      value: "staged",
      label: "Review staged changes",
      description: "index only",
    },
    {
      value: "baseBranch",
      label: "Review against a base branch",
      description: defaultBranch ? `(default branch: ${defaultBranch})` : "",
    },
    {
      value: "commit",
      label: "Review a commit",
      description: "recent commit diff",
    },
  ];
  const selectedValue = await showSelectableList(ctx, {
    title: "Select review target",
    items: targetItems,
    helpText: "Enter to confirm • esc to cancel",
    selectedIndex: Math.max(
      0,
      targetItems.findIndex((item) => item.value === smartDefault),
    ),
  });
  if (!selectedValue) return undefined;

  let selection: ReviewSelection | undefined;
  if (selectedValue === "uncommitted") {
    selection = {
      label: "uncommitted changes",
      request: { target: { type: "uncommitted" } },
    };
  } else if (selectedValue === "staged") {
    selection = {
      label: "staged changes",
      request: { target: { type: "staged" } },
    };
  } else if (selectedValue === "baseBranch") {
    const branches = await listReviewBranches(pi, ctx.cwd);
    if (branches.length === 0) {
      ctx.ui.notify("No branches available for base-branch review.", "warning");
      return undefined;
    }
    const branch = await showSelectableList(ctx, {
      title: "Select base branch",
      items: branches.map((branchName) => ({
        value: branchName,
        label: branchName,
        description:
          defaultBranch && branchName === defaultBranch ? "(default)" : "",
      })),
      filterPrompt: "Filter branches",
      helpText: "Type to filter • enter to select • esc to cancel",
      selectedIndex: Math.max(
        0,
        branches.findIndex((branchName) => branchName === defaultBranch),
      ),
    });
    if (!branch) return undefined;
    selection = {
      label: `base branch ${branch}`,
      request: { target: { type: "baseBranch", branch } },
    };
  } else {
    const commits = await listReviewCommits(pi, ctx.cwd);
    if (commits.length === 0) {
      ctx.ui.notify("No commits available for review.", "warning");
      return undefined;
    }
    const commitSha = await showSelectableList(ctx, {
      title: "Select commit",
      items: commits.map((commit) => ({
        value: commit.sha,
        label: commit.label,
        description: "",
      })),
      filterPrompt: "Filter commits",
      helpText: "Type to filter • enter to select • esc to cancel",
    });
    if (!commitSha) return undefined;
    selection = {
      label: `commit ${commitSha.slice(0, 12)}`,
      request: { target: { type: "commit", sha: commitSha } },
    };
  }

  return promptForOptionalReviewInstructions(ctx, selection);
}

function showCommandEntry(pi: ExtensionAPI, markdown: string) {
  pi.appendEntry(SUBAGENT_MARKDOWN_ENTRY_TYPE, { markdown });
}

function sendReviewMessage(pi: ExtensionAPI, markdown: string, content: string) {
  pi.sendMessage({
    customType: SUBAGENT_REVIEW_MESSAGE_TYPE,
    content,
    display: true,
    details: { markdown },
  });
}

export default function subagentExtension(pi: ExtensionAPI) {
  const activeRuns = new Map<string, SubagentRunState>();
  const recentRuns: SubagentRunState[] = [];
  const completedExploreCache = new Map<string, ExploreCacheRecord>();
  const activeExploreByKey = new Map<string, ActiveExploration>();
  let workspaceGeneration = 0;
  let sessionExploreTokens = 0;
  const widget = new SubagentWidget(() => [
    ...activeRuns.values(),
    ...recentRuns,
  ]);

  const rememberRun = (run: SubagentRunState) => {
    recentRuns.unshift(serializeRun(run) as SubagentRunState);
    if (recentRuns.length > MAX_RECENT_RUNS) recentRuns.splice(MAX_RECENT_RUNS);
  };

  const runTokenCount = (run: SubagentRunState) =>
    run.tasks.reduce((total, task) => total + Math.max(0, task.tokenCount || 0), 0);

  const restoreExploreState = (ctx: ExtensionContext) => {
    const restored = restoreExploreCacheState(ctx.sessionManager.getBranch() as any[]);
    completedExploreCache.clear();
    for (const [key, record] of restored.records) completedExploreCache.set(key, record);
    const reviewRuns = recentRuns.filter((run) => run.workflow === "review");
    recentRuns.splice(
      0,
      recentRuns.length,
      ...restored.runs.slice(0, MAX_RECENT_RUNS),
      ...reviewRuns,
    );
    if (recentRuns.length > MAX_RECENT_RUNS) recentRuns.splice(MAX_RECENT_RUNS);
    workspaceGeneration = restored.workspaceGeneration;
    sessionExploreTokens = restored.tokens;
  };

  const workspaceRevisionFor = async (
    tasks: SubagentTaskInput[],
    signal?: AbortSignal,
  ): Promise<string> => {
    const parts: Array<Record<string, unknown>> = [];
    const directories = [...new Set(tasks.map((task) => task.cwd).filter((cwd): cwd is string => Boolean(cwd)))].sort();
    for (const cwd of directories) {
      signal?.throwIfAborted();
      const execOptions = { cwd, signal } as { cwd: string; signal?: AbortSignal };
      const root = await pi.exec("git", ["rev-parse", "--show-toplevel"], execOptions);
      if ((root.code ?? 1) !== 0) {
        parts.push({ cwd, kind: "directory" });
        continue;
      }
      const repoRoot = root.stdout.trim();
      const [head, status] = await Promise.all([
        pi.exec("git", ["rev-parse", "--verify", "HEAD"], { ...execOptions, cwd: repoRoot }),
        pi.exec("git", ["status", "--porcelain=v2", "-z", "--untracked-files=normal"], { ...execOptions, cwd: repoRoot }),
      ]);
      parts.push({
        cwd,
        repoRoot,
        head: (head.code ?? 1) === 0 ? head.stdout.trim() : "unborn",
        status: status.stdout,
      });
    }
    return hashWorkspaceRevision(parts, workspaceGeneration);
  };

  type WorkflowExecutionOptions = {
    systemPrompt: string;
    parseOutput: (markdown: string) => ParsedSubagentOutput;
    buildRepairPrompt?: (
      parsed: ParsedSubagentOutput,
      rawResponse: string,
    ) => string | undefined;
    onUpdate?: (update: unknown) => void;
    signal?: AbortSignal;
    ctx: ExtensionContext | ExtensionCommandContext;
  };

  const executeInternalTask = async (
    workflow: SubagentWorkflow,
    taskInput: SubagentTaskInput,
    options: WorkflowExecutionOptions,
  ) => {
    const taskState: SubagentTaskState = {
      workflow,
      index: 0,
      taskId: createTaskId(createRunId(), 0),
      task: taskInput.task,
      label: taskInput.label?.trim() || taskInput.task.trim(),
      intent: taskInput.intent,
      model: taskInput.model,
      thinkingLevel: taskInput.thinkingLevel,
      cwd: taskInput.cwd,
      metadata: taskInput.metadata,
      state: "pending",
      toolUses: 0,
      turnCount: 0,
      tokenCount: 0,
      responseText: "",
      history: [],
      recentTools: [],
      recentOutputLines: [],
    };

    return runSingleTask(taskState, {
      parentCtx: options.ctx,
      emitRunUpdate: () => undefined,
      signal: options.signal,
      systemPrompt: options.systemPrompt,
      parseOutput: options.parseOutput,
      buildRepairPrompt: options.buildRepairPrompt,
    });
  };

  const executeWorkflow = async (
    workflow: SubagentWorkflow,
    taskInputs: SubagentTaskInput[],
    options: WorkflowExecutionOptions,
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
        intent: task.intent,
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
      pi.appendEntry(SUBAGENT_TASK_ENTRY_TYPE, {
        workflow,
        taskId: taskState.taskId,
        label: taskState.label,
        task: taskState.task,
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
            buildRepairPrompt: options.buildRepairPrompt,
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

  const exploreToolResult = (
    record: ExploreCacheRecord,
    options: {
      launched: boolean;
      matchKind?: "active" | "exact" | "similar";
      similarity?: number;
    },
  ) => {
    let text = record.content;
    if (!options.launched) {
      const ageSeconds = Math.max(0, Math.round((Date.now() - record.completedAt) / 1000));
      if (record.run.state !== "success") {
        text = [
          `Equivalent exploration ${record.run.runId} finished with ${record.run.state} state ${ageSeconds}s ago.`,
          "No retry was launched during the failure cooldown. A deliberate retry requires the user-only /explore-fresh command.",
          record.content,
        ].filter(Boolean).join("\n\n");
      } else if (options.matchKind === "similar") {
        text = [
          `This request is ${Math.round((options.similarity ?? 0) * 100)}% similar to successful run ${record.run.runId}.`,
          "Reusing its findings; no new subagent was launched. A deliberate independent replication requires /explore-fresh.",
          record.content,
        ].filter(Boolean).join("\n\n");
      } else {
        text = [
          `Equivalent exploration already ${options.matchKind === "active" ? "completed through the active single-flight run" : "completed"} as ${record.run.runId}.`,
          "Reusing that result; no new subagent was launched.",
          record.content,
        ].filter(Boolean).join("\n\n");
      }
    }

    return {
      content: [{ type: "text" as const, text }],
      details: {
        workflow: "explore",
        mode: record.run.mode,
        runId: record.run.runId,
        results: record.results,
        run: record.run,
        cache: createExploreCacheMetadata(record, options.launched),
        deduplicated: !options.launched,
        matchType: options.matchKind,
        similarity: options.similarity,
      },
    };
  };

  const launchExploration = (
    tasks: SubagentTaskInput[],
    workspaceRevision: string,
    key: string,
    options: WorkflowExecutionOptions & {
      forceFresh?: boolean;
      persistCacheEntry?: boolean;
    },
  ): ActiveExploration => {
    if (activeExploreByKey.size >= MAX_ACTIVE_EXPLORE_RUNS) {
      throw new Error(
        `Explore concurrency limit reached (${MAX_ACTIVE_EXPLORE_RUNS} active runs). Use explore_status instead of launching more work.`,
      );
    }
    if (sessionExploreTokens >= MAX_EXPLORE_SESSION_TOKENS) {
      throw new Error(
        `Explore session token budget reached (${MAX_EXPLORE_SESSION_TOKENS} child tokens). Start a new session before launching more subagents.`,
      );
    }

    const activeKey = options.forceFresh ? `${key}:fresh:${createRunId()}` : key;
    const controller = new AbortController();
    const active = {
      key: activeKey,
      controller,
      promise: undefined as unknown as Promise<ExploreCacheRecord>,
      waiters: 0,
      settled: false,
    };
    active.promise = (async () => {
      const { run, results } = await executeWorkflow("explore", tasks, {
        ...options,
        signal: controller.signal,
      });
      const serializedRun = serializeRun(run) as SubagentRunState;
      const record: ExploreCacheRecord = {
        key,
        workspaceRevision,
        tasks: tasks.map((task) => ({ ...task })),
        run: serializedRun,
        results,
        content: renderFinalExploreResults(run.runId, run.mode, results),
        completedAt: run.endedAt ?? Date.now(),
      };
      sessionExploreTokens += runTokenCount(serializedRun);
      rememberExploration(completedExploreCache, record);
      if (options.persistCacheEntry) {
        pi.appendEntry(EXPLORE_CACHE_ENTRY_TYPE, { record, launched: true });
      }
      return record;
    })().finally(() => {
      active.settled = true;
      activeExploreByKey.delete(activeKey);
    });
    activeExploreByKey.set(activeKey, active);
    return active;
  };

  const executeExploreTasks = async (
    tasks: SubagentTaskInput[],
    options: WorkflowExecutionOptions & {
      forceFresh?: boolean;
      persistCacheEntry?: boolean;
    },
  ) => {
    const workspaceRevision = await workspaceRevisionFor(tasks, options.signal);
    const key = createExplorationKey(tasks, workspaceRevision);

    if (!options.forceFresh) {
      const active = activeExploreByKey.get(key);
      if (active) {
        options.onUpdate?.({
          content: [{ type: "text", text: "Joining an equivalent active exploration run." }],
          details: { workflow: "explore", deduplicated: true, matchType: "active" },
        });
        const record = await subscribeToActiveExploration(active, options.signal);
        return exploreToolResult(record, { launched: false, matchKind: "active" });
      }

      const match = findReusableExploration(
        completedExploreCache.values(),
        tasks,
        key,
        workspaceRevision,
      );
      if (match) {
        return exploreToolResult(match.record, {
          launched: false,
          matchKind: match.kind,
          similarity: match.similarity,
        });
      }
    }

    const active = launchExploration(tasks, workspaceRevision, key, options);
    const record = await subscribeToActiveExploration(active, options.signal);
    return exploreToolResult(record, { launched: true });
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

    const run = findRunOrThrow(runs, params.runId);

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
    let cleanup: (() => Promise<void>) | undefined;
    const request = {
      ...selection.request,
      projectGuidelinesAllowed: ctx.isProjectTrusted(),
    };
    try {
      const created = await createReviewContext(
        pi,
        request,
        ctx.cwd,
        signal,
      );
      cleanup = created.cleanup;
      let context = created.context;

      try {
        const briefTask = await createReviewBriefTask(
          context,
          request,
          ctx.cwd,
        );
        const briefResult = await executeInternalTask("review", briefTask, {
          systemPrompt: REVIEW_BRIEF_PROMPT,
          parseOutput: parseReviewBriefOutput,
          signal,
          ctx,
        });

        if (signal?.aborted || briefResult.status === "aborted") {
          return { status: "aborted" };
        }

        const briefMarkdown =
          briefResult.rawResponse?.trim() ||
          (typeof briefResult.data?.changeBriefMarkdown === "string"
            ? briefResult.data.changeBriefMarkdown.trim()
            : "");
        const briefWarnings = briefMarkdown
          ? []
          : briefResult.status === "success"
            ? ["Change brief generation returned no usable brief."]
            : [
                `Change brief generation completed with ${briefResult.status} state${briefResult.error ? `: ${briefResult.error}` : "."}`,
              ];
        context = withReviewChangeBrief(context, briefMarkdown, briefWarnings);
      } catch (error) {
        if (signal?.aborted) return { status: "aborted" };
        context = withReviewChangeBrief(context, undefined, [
          `Change brief generation failed: ${error instanceof Error ? error.message : String(error)}`,
        ]);
      }

      const tasks = await createReviewTasksForContext(
        context,
        request,
        ctx.cwd,
      );
      const { run, results } = await executeWorkflow("review", tasks, {
        systemPrompt: REVIEWER_PROMPT,
        parseOutput: parseReviewOutput,
        buildRepairPrompt: buildReviewRepairPrompt,
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
      sendReviewMessage(
        pi,
        reviewMarkdown,
        buildReviewContextMessage(reviewMarkdown) ?? reviewMarkdown,
      );

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
    } finally {
      await cleanup?.();
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
      else showCommandEntry(pi, parsed.error);
      return;
    }

    if (!parsed && ctx.mode !== "tui" && ctx.mode !== "rpc") {
      showCommandEntry(pi, REVIEW_COMMAND_USAGE);
      return;
    }

    const selection = parsed ?? (await promptForReviewSelection(pi, ctx));
    if (!selection) return;

    let result: ReviewExecutionResult;
    if (ctx.mode === "tui") {
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
        showCommandEntry(pi, `Review failed: ${result.message}`);
      }
      return;
    }

    switch (result.status) {
      case "success":
        ctx.ui.notify(
          `Review finished for ${selection.label}. Findings are now available to the main agent.`,
          "info",
        );
        return;
      case "aborted":
        ctx.ui.notify(`Review cancelled for ${selection.label}.`, "info");
        return;
      case "partial":
        ctx.ui.notify(
          `${result.message} Findings are now available to the main agent.`,
          "warning",
        );
        return;
      case "error":
        ctx.ui.notify(`Review failed: ${result.message}`, "error");
        return;
    }
  };

  pi.on("tool_result", (event) => {
    if (event.isError || !["edit", "write", "bash"].includes(event.toolName)) return;
    workspaceGeneration += 1;
    pi.appendEntry(WORKSPACE_GENERATION_ENTRY_TYPE, {
      generation: workspaceGeneration,
      timestamp: Date.now(),
    });
  });

  pi.on("session_start", (_event, ctx) => {
    restoreExploreState(ctx);
    if (!ctx.hasUI) return;
    widget.setUICtx(ctx.ui, ctx.mode);
    widget.update();
  });

  pi.on("session_tree", (_event, ctx) => {
    restoreExploreState(ctx);
    widget.update();
  });

  pi.on("agent_settled", () => {
    widget.dispose();
  });

  pi.on("session_shutdown", () => {
    for (const active of activeExploreByKey.values()) {
      active.controller.abort(new Error("Exploration session shut down."));
    }
    activeExploreByKey.clear();
    widget.dispose();
  });

  pi.registerEntryRenderer(
    SUBAGENT_TASK_ENTRY_TYPE,
    (entry, { expanded }, theme) => {
      const details = entry.data as
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

  pi.registerEntryRenderer(
    SUBAGENT_MARKDOWN_ENTRY_TYPE,
    (entry, { expanded }, theme) => {
      const details = entry.data as { markdown?: string } | undefined;
      if (!details?.markdown) return undefined;
      if (!expanded) {
        return new Text(renderMarkdownPreview(details.markdown, theme), 0, 0);
      }
      return new Markdown(details.markdown, 0, 0, getMarkdownTheme());
    },
  );

  pi.registerMessageRenderer(
    SUBAGENT_REVIEW_MESSAGE_TYPE,
    (message, { expanded }, theme) => {
      const details = message.details as { markdown?: string } | undefined;
      if (!details?.markdown) return undefined;
      if (!expanded) return new Text(renderMarkdownPreview(details.markdown, theme), 0, 0);
      return new Markdown(details.markdown, 0, 0, getMarkdownTheme());
    },
  );

  pi.registerMessageRenderer(
    SUBAGENT_EXPLORE_MESSAGE_TYPE,
    (message, { expanded }, theme) => {
      const details = message.details as { markdown?: string } | undefined;
      const markdown = details?.markdown
        ?? (typeof message.content === "string" ? message.content : "");
      if (!markdown) return undefined;
      if (!expanded) return new Text(renderMarkdownPreview(markdown, theme), 0, 0);
      return new Markdown(markdown, 0, 0, getMarkdownTheme());
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

      showCommandEntry(
        pi,
        renderTaskHistoryMarkdown(result.task, result.run),
      );
    },
  });

  pi.registerCommand("explore-fresh", {
    description: "Explicitly authorize a fresh exploration run, bypassing duplicate reuse",
    handler: async (args, ctx) => {
      const parsed = parseFreshExploreArgs(args ?? "");
      if (!parsed.task) {
        ctx.ui.notify("Usage: /explore-fresh [fast|balanced|deep] <task>", "warning");
        return;
      }

      const tasks = buildExploreTaskInputs(
        { task: parsed.task, intent: parsed.intent, cwd: ctx.cwd },
        ctx.cwd,
      );
      try {
        const revision = await workspaceRevisionFor(tasks);
        const key = createExplorationKey(tasks, revision);
        const previous = findReusableExploration(
          completedExploreCache.values(),
          tasks,
          key,
          revision,
        );
        if (previous && ctx.hasUI) {
          const age = Math.max(0, Math.round((Date.now() - previous.record.completedAt) / 1000));
          const tokens = runTokenCount(previous.record.run);
          const confirmed = await ctx.ui.confirm(
            "Launch fresh exploration?",
            `Matching run ${previous.record.run.runId} completed ${age}s ago with ${tokens} child tokens. Launch another independent run?`,
          );
          if (!confirmed) return;
        }

        const result = await executeExploreTasks(tasks, {
          systemPrompt: EXPLORER_PROMPT,
          parseOutput: parseExploreOutput,
          ctx,
          forceFresh: true,
          persistCacheEntry: true,
        });
        const markdown = result.content[0]?.text ?? "Fresh exploration completed.";
        pi.sendMessage(
          {
            customType: SUBAGENT_EXPLORE_MESSAGE_TYPE,
            content: markdown,
            display: true,
            details: { markdown, ...(result.details ?? {}) },
          },
          { deliverAs: "nextTurn" },
        );
        ctx.ui.notify("Fresh exploration completed.", "info");
      } catch (error) {
        ctx.ui.notify(
          `Fresh exploration failed: ${error instanceof Error ? error.message : String(error)}`,
          "error",
        );
      }
    },
  });

  pi.registerCommand("review", {
    description:
      "Run the fixed review pair against uncommitted changes, staged changes, a base branch, or a commit",
    handler: async (args, ctx) => {
      await executeReviewCommand(args, ctx);
    },
  });

  pi.registerTool({
    name: "explore",
    label: "Explore",
    description:
      "Run one or more isolated read-only exploration subagents and return compressed findings. Use optional intent hints like fast, balanced, or deep; the extension maps them to safe internal models.",
    promptSnippet:
      "Delegate repo, docs, web, or source exploration to isolated subagents. Use this for information gathering and context compression.",
    promptGuidelines: [
      "Use explore for exploration tasks where intermediate retrieval steps do not need to pollute the main context.",
      "Prefer parallel explore tasks when the information sources are independent, such as repo scan + web docs + upstream implementation lookup.",
      "Keep explore tasks read-only and focused on finding and summarizing information.",
      "Use explore intent instead of raw model names: fast for lightweight scans, balanced for the default tradeoff, deep for heavier synthesis.",
      "If explore intent is omitted or unclear, the extension falls back to a safe balanced profile automatically.",
      "Use multiple explore tasks when the work is naturally parallel.",
      "If explore reports an infrastructure or tool-access failure, do not retry the same exploration; report the failure and continue with available local tools.",
      "Do not use explore for formal audits or code review; /review is user-triggered.",
      "Before calling explore, use explore_status when a relevant exploration may already exist; never automatically rerun an identical or substantially overlapping task.",
      "Repeated, rephrased, fresh, or independent wording is not sufficient authorization for explore to spend on another run; exact and near-duplicate requests are reused automatically.",
      "Use the structured explore result directly in your response instead of redoing the exploration yourself.",
      "When explore returns multiple task results, synthesize across those results instead of discarding their structure.",
      "A deliberate independent rerun requires the user-only /explore-fresh command; the agent-facing explore tool cannot bypass duplicate protection.",
    ],
    parameters: exploreParamsSchema,
    renderCall(args, theme) {
      return renderExploreToolCall(args, theme);
    },
    renderResult(result, options, theme) {
      return renderExploreToolResult(result, options, theme);
    },
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const tasks = buildExploreTaskInputs(
        params as {
          task?: string;
          intent?: string;
          cwd?: string;
          tasks?: Array<{ task: string; intent?: string; cwd?: string }>;
        },
        ctx.cwd,
      );

      try {
        return await executeExploreTasks(tasks, {
          systemPrompt: EXPLORER_PROMPT,
          parseOutput: parseExploreOutput,
          onUpdate,
          signal,
          ctx,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(`Explore run failed: ${message}`);
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
    promptGuidelines: [
      "Use explore_status to inspect active or recent explore runs instead of starting duplicate exploration work.",
    ],
    parameters: statusSchema,
    async execute(_toolCallId, params) {
      return executeStatus(
        "explore",
        params as { action: "list" | "get"; runId?: string },
      );
    },
  });
}
