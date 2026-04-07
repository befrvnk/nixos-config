import type { Message, Model } from "@mariozechner/pi-ai";
import {
  createAgentSession,
  DefaultResourceLoader,
  SessionManager,
} from "@mariozechner/pi-coding-agent";
import { parseStructuredOutput } from "./formatting.js";
import { createGuardedExplorationTools } from "./child-guard.js";
import { EXPLORER_PROMPT } from "./prompt.js";
import {
  MAX_RECENT_OUTPUT_LINES,
  MAX_RECENT_TOOLS,
  type ExploreTaskResult,
  type ExploreTaskState,
} from "./types.js";

type ModelRegistryLike = {
  find(provider: string, modelId: string): Model<any> | undefined;
  getAvailable?(): Promise<Model<any>[]>;
};

type ParentContextLike = {
  model?: Model<any>;
  modelRegistry?: ModelRegistryLike;
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

function looksLikeStructuredExploreResult(text: string): boolean {
  return /^##\s+Summary\b/m.test(text)
    && /^##\s+Sources\b/m.test(text)
    && /^##\s+Key Findings\b/m.test(text)
    && /^##\s+Next Steps\b/m.test(text);
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
  if (!requestedModel?.trim()) return parentCtx.model;

  const parsed = parseModelRef(requestedModel);
  if (!parsed) return parentCtx.model;

  if (parsed.provider) {
    const resolved = parentCtx.modelRegistry?.find(parsed.provider, parsed.id);
    if (!resolved) {
      throw new Error(`Unknown model: ${parsed.provider}/${parsed.id}`);
    }
    return resolved;
  }

  if (parentCtx.model?.id === parsed.id) {
    return parentCtx.model;
  }

  const available = await parentCtx.modelRegistry?.getAvailable?.();
  const matches = available?.filter((model) => model.id === parsed.id) ?? [];
  if (matches.length === 1) return matches[0];
  if (matches.length > 1) {
    const refs = matches.map((model) => `${model.provider}/${model.id}`).join(", ");
    throw new Error(`Ambiguous model "${parsed.id}". Matches: ${refs}`);
  }

  throw new Error(`Unknown model: ${parsed.id}`);
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
        // JavaScript runs this synchronous increment without interleaving, so
        // each worker claims a unique index before awaiting the task body.
        const index = next++;
        if (index >= items.length) return;
        results[index] = await fn(items[index]!, index);
      }
    }),
  );
  return results;
}

export async function runSingleTask(
  taskState: ExploreTaskState,
  parentCtx: ParentContextLike,
  emitRunUpdate: () => void,
  signal?: AbortSignal,
): Promise<ExploreTaskResult> {
  taskState.state = "running";
  taskState.startedAt = Date.now();
  emitRunUpdate();

  const repositoryRoot = taskState.cwd ?? process.cwd();
  const scopedTask = [
    `Working directory: ${repositoryRoot}`,
    `Repository root for local inspection: ${repositoryRoot}`,
    `For repository-local investigation, only inspect paths under ${repositoryRoot}.`,
    "Do not inspect absolute paths outside that repository unless the task explicitly requires external investigation or upstream source lookup.",
    `Task: ${taskState.task}`,
  ].join("\n");

  let settled = false;
  let aborted = false;
  let bestStructuredAssistantText = "";
  let finalAssistantText = "";
  let fallbackAssistantText = "";
  let promptError: string | undefined;

  const finish = (result: ExploreTaskResult) => {
    if (settled) return result;
    settled = true;
    taskState.endedAt = Date.now();
    taskState.summary = result.summary;
    taskState.sources = result.sources;
    taskState.keyFindings = result.keyFindings;
    taskState.suggestedNextSteps = result.suggestedNextSteps;
    taskState.error = result.error;
    taskState.state =
      result.status === "success"
        ? "success"
        : result.status === "aborted"
          ? "aborted"
          : "error";
    taskState.currentTool = undefined;
    emitRunUpdate();
    return result;
  };

  try {
    const model = await resolveModel(taskState.model, parentCtx);
    const resourceLoader = new DefaultResourceLoader({
      cwd: repositoryRoot,
      noExtensions: true,
      noThemes: true,
      appendSystemPromptOverride: (base) => [...base, EXPLORER_PROMPT],
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
        if (role === "assistant") taskState.responseText = "";
        return;
      }

      if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
        taskState.responseText = `${taskState.responseText}${String(event.assistantMessageEvent.delta ?? "")}`.slice(-600);
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
          if (typeof message.usage?.totalTokens === "number") {
            taskState.tokenCount = message.usage.totalTokens;
          }
          if (text && looksLikeStructuredExploreResult(text)) {
            bestStructuredAssistantText = text;
          }
          if (text && message.stopReason === "stop") {
            finalAssistantText = text;
          }
          if (message.stopReason === "error" && message.errorMessage) {
            taskState.error = message.errorMessage;
          }
          if (message.stopReason === "aborted") {
            aborted = true;
          }
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
      await session.prompt(scopedTask);
    } catch (error) {
      promptError = error instanceof Error ? error.message : String(error);
    } finally {
      fallbackAssistantText = getLastAssistantText(session.messages as Array<{ role?: string; content?: unknown }>);
      unsubscribe();
      if (signal) signal.removeEventListener("abort", abortHandler);
      session.dispose();
    }

    const bestAnswerText = bestStructuredAssistantText || finalAssistantText || fallbackAssistantText;
    const parsed = parseStructuredOutput(bestAnswerText);

    if (aborted) {
      return finish({
        task: taskState.task,
        model: taskState.model,
        cwd: taskState.cwd,
        status: "aborted",
        summary: parsed.summary,
        sources: parsed.sources,
        keyFindings: parsed.keyFindings,
        suggestedNextSteps: parsed.suggestedNextSteps,
        error: taskState.error || promptError || "Subagent aborted",
      });
    }

    if (promptError) {
      return finish({
        task: taskState.task,
        model: taskState.model,
        cwd: taskState.cwd,
        status: "error",
        summary: parsed.summary,
        sources: parsed.sources,
        keyFindings: parsed.keyFindings,
        suggestedNextSteps: parsed.suggestedNextSteps,
        error: promptError,
      });
    }

    return finish({
      task: taskState.task,
      model: taskState.model,
      cwd: taskState.cwd,
      status: "success",
      summary: parsed.summary,
      sources: parsed.sources,
      keyFindings: parsed.keyFindings,
      suggestedNextSteps: parsed.suggestedNextSteps,
    });
  } catch (error) {
    const parsed = parseStructuredOutput(bestStructuredAssistantText || finalAssistantText);
    const message = error instanceof Error ? error.message : String(error);
    return finish({
      task: taskState.task,
      model: taskState.model,
      cwd: taskState.cwd,
      status: aborted ? "aborted" : "error",
      summary: parsed.summary,
      sources: parsed.sources,
      keyFindings: parsed.keyFindings,
      suggestedNextSteps: parsed.suggestedNextSteps,
      error: message,
    });
  }
}
