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
  renderTaskHistoryMarkdown,
  serializeRun,
  uniqueNonEmptyStrings,
} from "./formatting.js";
import {
  findTaskById,
  parseReviewCommandArgs,
  REVIEW_COMMAND_USAGE,
  type ReviewSelection,
} from "./commands.js";
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
  MAX_PARALLEL_TASKS,
  MAX_RECENT_RUNS,
  type ParsedSubagentOutput,
  type SubagentRunState,
  type SubagentTaskInput,
  type SubagentTaskState,
} from "./types.js";
import { renderSubagentTaskMessage, SubagentWidget } from "./ui.js";
const SUBAGENT_TASK_ENTRY_TYPE = "subagent-task";
const SUBAGENT_MARKDOWN_ENTRY_TYPE = "subagent-markdown";
const SUBAGENT_REVIEW_MESSAGE_TYPE = "subagent-review";
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
  const widget = new SubagentWidget(() => [
    ...activeRuns.values(),
    ...recentRuns,
  ]);

  const rememberRun = (run: SubagentRunState) => {
    recentRuns.unshift(serializeRun(run) as SubagentRunState);
    if (recentRuns.length > MAX_RECENT_RUNS) recentRuns.splice(MAX_RECENT_RUNS);
  };

  type WorkflowExecutionOptions = {
    systemPrompt: string;
    parseOutput: (markdown: string) => ParsedSubagentOutput;
    buildRepairPrompt?: (
      parsed: ParsedSubagentOutput,
      rawResponse: string,
    ) => string | undefined;
    signal?: AbortSignal;
    ctx: ExtensionContext | ExtensionCommandContext;
  };

  const executeInternalTask = async (
    taskInput: SubagentTaskInput,
    options: WorkflowExecutionOptions,
  ) => {
    const taskState: SubagentTaskState = {
      workflow: "review",
      index: 0,
      taskId: createTaskId(createRunId(), 0),
      task: taskInput.task,
      label: taskInput.label?.trim() || taskInput.task.trim(),
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
    taskInputs: SubagentTaskInput[],
    options: WorkflowExecutionOptions,
  ) => {
    const runId = createRunId();
    const run: SubagentRunState = {
      workflow: "review",
      runId,
      mode: taskInputs.length === 1 ? "single" : "parallel",
      state: "running",
      startedAt: Date.now(),
      tasks: taskInputs.map((task, index) => ({
        workflow: "review",
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
      widget.update();
    };

    activeRuns.set(run.runId, run);
    for (const taskState of run.tasks) {
      pi.appendEntry(SUBAGENT_TASK_ENTRY_TYPE, {
        workflow: "review",
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
        const briefResult = await executeInternalTask(briefTask, {
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
      const { run, results } = await executeWorkflow(tasks, {
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

  pi.on("session_start", (_event, ctx) => {
    if (!ctx.hasUI) return;
    widget.setUICtx(ctx.ui, ctx.mode);
    widget.update();
  });

  pi.on("session_tree", () => {
    widget.update();
  });

  pi.on("agent_settled", () => {
    widget.dispose();
  });

  pi.on("session_shutdown", () => {
    widget.dispose();
  });

  pi.registerEntryRenderer(
    SUBAGENT_TASK_ENTRY_TYPE,
    (entry, { expanded }, theme) => {
      const details = entry.data as
        | {
            workflow?: unknown;
            taskId: string;
            label: string;
            task: string;
          }
        | undefined;
      if (!details || details.workflow !== "review") return undefined;
      return renderSubagentTaskMessage(
        { ...details, workflow: "review" },
        expanded,
        theme,
      );
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

  pi.registerCommand("review", {
    description:
      "Run the fixed review pair against uncommitted changes, staged changes, a base branch, or a commit",
    handler: async (args, ctx) => {
      await executeReviewCommand(args, ctx);
    },
  });

}
