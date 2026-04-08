import type { Message, Model } from "@mariozechner/pi-ai";
import {
  createAgentSession,
  DefaultResourceLoader,
  SessionManager,
} from "@mariozechner/pi-coding-agent";
import { createGuardedExplorationTools } from "./child-guard.js";
import { cleanParsedOutput, extractLatestProgress, stripProgressBlocks } from "./progress.js";
import type {
  ParsedSubagentOutput,
  SubagentTaskResult,
  SubagentTaskState,
} from "./types.js";
import {
  COPILOT_PROVIDER,
  MAX_RECENT_OUTPUT_LINES,
  MAX_RECENT_TOOLS,
} from "./types.js";

type ModelRegistryLike = {
  find(provider: string, modelId: string): Model<any> | undefined;
  getAvailable?(): Promise<Model<any>[]>;
};

type ParentContextLike = {
  model?: Model<any>;
  modelRegistry?: ModelRegistryLike;
};

type RunTaskOptions = {
  parentCtx: ParentContextLike;
  emitRunUpdate: () => void;
  signal?: AbortSignal;
  systemPrompt: string;
  parseOutput: (markdown: string) => ParsedSubagentOutput;
};

function extractTextFromContent(content: unknown): string {
  if (typeof content === "string") return content.trim();
  if (!Array.isArray(content)) return "";
  const parts: string[] = [];
  for (const part of content) {
    if (part && typeof part === "object" && (part as { type?: string }).type === "text") {
      parts.push(String((part as { text?: unknown }).text ?? ""));
    }
  }
  return parts.join("\n").trim();
}

function pushLimited(items: string[], value: string, limit: number): void {
  if (!value.trim()) return;
  items.push(value.trim());
  if (items.length > limit) items.splice(0, items.length - limit);
}

function previewTool(toolName: string, args: Record<string, unknown> | undefined): string {
  if (!args) return toolName;
  switch (toolName) {
    case "bash":
      return `$ ${String(args.command ?? "").trim()}`;
    case "read": {
      const filePath = String(args.path ?? "");
      const offset = typeof args.offset === "number" ? `:${args.offset}` : "";
      return `read ${filePath}${offset}`;
    }
    case "grep":
      return `grep ${String(args.pattern ?? "")} in ${String(args.path ?? ".")}`;
    case "find":
      return `find ${String(args.pattern ?? "*")} in ${String(args.path ?? ".")}`;
    case "ls":
      return `ls ${String(args.path ?? ".")}`;
    default:
      return toolName;
  }
}

function parseModelRef(model: string | undefined): { provider?: string; id: string } | undefined {
  if (!model?.trim()) return undefined;
  const trimmed = model.trim();
  const slash = trimmed.indexOf("/");
  if (slash === -1) return { id: trimmed };
  return { provider: trimmed.slice(0, slash), id: trimmed.slice(slash + 1) };
}

async function resolveModel(
  requestedModel: string | undefined,
  parentCtx: ParentContextLike,
): Promise<Model<any> | undefined> {
  if (!requestedModel?.trim()) {
    if (parentCtx.model?.provider === COPILOT_PROVIDER) return parentCtx.model;
    const fallback = parentCtx.modelRegistry?.find(COPILOT_PROVIDER, "gpt-5.4");
    if (fallback) return fallback;
    const current = parentCtx.model ? `${parentCtx.model.provider}/${parentCtx.model.id}` : "none";
    throw new Error(
      `Subagents only support GitHub Copilot models. Current model: ${current}. Pass a GitHub Copilot model explicitly.`,
    );
  }

  const parsed = parseModelRef(requestedModel);
  if (!parsed) return undefined;

  if (parsed.provider && parsed.provider !== COPILOT_PROVIDER) {
    throw new Error(`Subagents only support ${COPILOT_PROVIDER} models. Requested provider: ${parsed.provider}`);
  }

  if (parentCtx.model?.provider === COPILOT_PROVIDER && parentCtx.model.id === parsed.id) {
    return parentCtx.model;
  }

  if (parsed.provider) {
    const resolved = parentCtx.modelRegistry?.find(COPILOT_PROVIDER, parsed.id);
    if (!resolved) throw new Error(`Unknown GitHub Copilot model: ${COPILOT_PROVIDER}/${parsed.id}`);
    return resolved;
  }

  const available = await parentCtx.modelRegistry?.getAvailable?.();
  const matches = (available ?? []).filter(
    (model) => model.provider === COPILOT_PROVIDER && model.id === parsed.id,
  );
  if (matches.length === 1) return matches[0];
  if (matches.length > 1) {
    const refs = matches.map((model) => `${model.provider}/${model.id}`).join(", ");
    throw new Error(`Ambiguous GitHub Copilot model "${parsed.id}". Matches: ${refs}`);
  }

  throw new Error(`Unknown GitHub Copilot model: ${parsed.id}`);
}

function getLastAssistantText(messages: Array<{ role?: string; content?: unknown }> | undefined): string {
  if (!messages) return "";
  for (let i = messages.length - 1; i >= 0; i--) {
    const message = messages[i];
    if (message?.role !== "assistant") continue;
    const text = extractTextFromContent(message.content);
    if (text) return text;
  }
  return "";
}

export async function mapWithConcurrencyLimit<TIn, TOut>(
  items: TIn[],
  limit: number,
  fn: (item: TIn, index: number) => Promise<TOut>,
): Promise<TOut[]> {
  if (items.length === 0) return [];
  const concurrency = Math.max(1, Math.min(limit, items.length));
  const results = new Array<TOut>(items.length);
  let next = 0;
  await Promise.all(
    new Array(concurrency).fill(null).map(async () => {
      while (true) {
        const index = next++;
        if (index >= items.length) return;
        results[index] = await fn(items[index]!, index);
      }
    }),
  );
  return results;
}

export async function runSingleTask(
  taskState: SubagentTaskState,
  options: RunTaskOptions,
): Promise<SubagentTaskResult> {
  const { parentCtx, emitRunUpdate, signal, systemPrompt, parseOutput } = options;
  taskState.state = "running";
  taskState.startedAt = Date.now();
  emitRunUpdate();

  let settled = false;
  let aborted = false;
  let bestAssistantText = "";
  let fallbackAssistantText = "";
  let streamingAssistantText = "";
  let promptError: string | undefined;

  const finish = (result: SubagentTaskResult) => {
    if (settled) return result;
    settled = true;
    taskState.endedAt = Date.now();
    taskState.summary = result.summary;
    taskState.data = result.data;
    taskState.error = result.error;
    taskState.state = result.status;
    taskState.currentTool = undefined;
    emitRunUpdate();
    return result;
  };

  try {
    const model = await resolveModel(taskState.model, parentCtx);
    const repositoryRoot = taskState.cwd ?? process.cwd();
    const resourceLoader = new DefaultResourceLoader({
      cwd: repositoryRoot,
      noExtensions: true,
      noThemes: true,
      appendSystemPromptOverride: (base) => [...base, systemPrompt],
    });
    await resourceLoader.reload();

    const createSessionOptions: Record<string, unknown> = {
      cwd: repositoryRoot,
      resourceLoader,
      tools: createGuardedExplorationTools(repositoryRoot),
      sessionManager: SessionManager.inMemory(repositoryRoot),
    };
    if (model) createSessionOptions.model = model;
    if (parentCtx.modelRegistry) createSessionOptions.modelRegistry = parentCtx.modelRegistry;

    const { session } = await createAgentSession(createSessionOptions as Parameters<typeof createAgentSession>[0]);

    const unsubscribe = session.subscribe((event: any) => {
      if (event.type === "message_start") {
        const role = event.message?.role;
        if (role === "assistant") {
          streamingAssistantText = "";
          taskState.responseText = "";
        }
        return;
      }

      if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
        streamingAssistantText = `${streamingAssistantText}${String(event.assistantMessageEvent.delta ?? "")}`.slice(-4000);
        taskState.responseText = stripProgressBlocks(streamingAssistantText).slice(-600);
        const progressItems = extractLatestProgress(streamingAssistantText);
        if (progressItems) taskState.progressItems = progressItems;
        emitRunUpdate();
        return;
      }

      if (event.type === "turn_end") {
        taskState.turnCount += 1;
        const totalTokens = event.message?.usage?.totalTokens;
        if (typeof totalTokens === "number") taskState.tokenCount = totalTokens;
        emitRunUpdate();
        return;
      }

      if (event.type === "tool_execution_start") {
        taskState.currentTool = previewTool(event.toolName ?? "tool", event.args ?? event.input ?? {});
        pushLimited(taskState.recentTools, taskState.currentTool, MAX_RECENT_TOOLS);
        emitRunUpdate();
        return;
      }

      if (event.type === "tool_execution_end") {
        taskState.currentTool = undefined;
        taskState.toolUses += 1;
        const toolText = extractTextFromContent(event.result?.content);
        if (toolText) {
          for (const line of toolText.split("\n").map((item) => item.trim()).filter(Boolean).slice(-4)) {
            pushLimited(taskState.recentOutputLines, line, MAX_RECENT_OUTPUT_LINES);
          }
        }
        emitRunUpdate();
        return;
      }

      if (event.type === "message_end" && event.message) {
        const message = event.message as Message;
        const text = extractTextFromContent(message.content);
        if (text) {
          for (const line of text.split("\n").map((item) => item.trim()).filter(Boolean).slice(-4)) {
            pushLimited(taskState.recentOutputLines, line, MAX_RECENT_OUTPUT_LINES);
          }
        }
        if (message.role === "assistant") {
          if (typeof message.usage?.totalTokens === "number") taskState.tokenCount = message.usage.totalTokens;
          if (text) {
            bestAssistantText = text;
            taskState.responseText = stripProgressBlocks(text).slice(-600);
            const progressItems = extractLatestProgress(text);
            if (progressItems) taskState.progressItems = progressItems;
          }
          if (message.stopReason === "error" && message.errorMessage) taskState.error = message.errorMessage;
          if (message.stopReason === "aborted") aborted = true;
        }
        emitRunUpdate();
      }
    });

    const abortHandler = () => {
      aborted = true;
      void session.abort();
    };

    if (signal) {
      if (signal.aborted) abortHandler();
      else signal.addEventListener("abort", abortHandler, { once: true });
    }

    try {
      await session.prompt(taskState.task);
    } catch (error) {
      promptError = error instanceof Error ? error.message : String(error);
    } finally {
      fallbackAssistantText = getLastAssistantText(session.messages as Array<{ role?: string; content?: unknown }>);
      unsubscribe();
      if (signal) signal.removeEventListener("abort", abortHandler);
      session.dispose();
    }

    const bestResponse = stripProgressBlocks(bestAssistantText || fallbackAssistantText);
    const parsed = cleanParsedOutput(parseOutput(bestResponse));

    if (aborted) {
      return finish({
        task: taskState.task,
        label: taskState.label,
        model: model ? `${model.provider}/${model.id}` : taskState.model,
        cwd: taskState.cwd,
        status: "aborted",
        summary: parsed.summary,
        data: parsed.data,
        error: taskState.error || promptError || "Subagent aborted",
        rawResponse: bestResponse,
        metadata: taskState.metadata,
      });
    }

    if (promptError) {
      return finish({
        task: taskState.task,
        label: taskState.label,
        model: model ? `${model.provider}/${model.id}` : taskState.model,
        cwd: taskState.cwd,
        status: "error",
        summary: parsed.summary,
        data: parsed.data,
        error: promptError,
        rawResponse: bestResponse,
        metadata: taskState.metadata,
      });
    }

    return finish({
      task: taskState.task,
      label: taskState.label,
      model: model ? `${model.provider}/${model.id}` : taskState.model,
      cwd: taskState.cwd,
      status: "success",
      summary: parsed.summary,
      data: parsed.data,
      rawResponse: bestResponse,
      metadata: taskState.metadata,
    });
  } catch (error) {
    const response = stripProgressBlocks(bestAssistantText || fallbackAssistantText);
    const parsed = cleanParsedOutput(parseOutput(response));
    const message = error instanceof Error ? error.message : String(error);
    return finish({
      task: taskState.task,
      label: taskState.label,
      model: taskState.model,
      cwd: taskState.cwd,
      status: aborted ? "aborted" : "error",
      summary: parsed.summary,
      data: parsed.data,
      error: message,
      rawResponse: response,
      metadata: taskState.metadata,
    });
  }
}
