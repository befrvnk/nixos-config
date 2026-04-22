import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { CONFIG_PATH, loadConfig, tryLoadConfig } from "./config.js";
import {
  formatDiagnostics,
  formatDocumentSymbols,
  formatLocations,
  formatWorkspaceSymbols,
  hoverToText,
} from "./formatting.js";
import { ROOT_MARKERS } from "./constants.js";
import {
  detectLanguage,
  detectProjectRoot,
  ensureActionSupportsPath,
  resolveFilePath,
  toTextDocumentIdentifier,
  toZeroIndexedPosition,
  walkParents,
} from "./paths.js";
import {
  DiagnosticsParams,
  DocumentSymbolsParams,
  LspQueryParams,
  PositionParams,
  PositionSearchParams,
  ReferencesParams,
  WorkspaceSymbolsParams,
} from "./schemas.js";
import {
  isLspNoProjectError,
  isLspReadinessTimeoutError,
  isUnsupportedLspMethodError,
  LspNoProjectError,
  ServerManager,
  type UnsupportedLspMethodError,
} from "./server.js";
import { formatLogDetails as renderLogDetails, formatStatusDetails as renderStatusDetails } from "./status.js";
import type { QueryAction, ServerStatus, SupportedLanguage } from "./types.js";
import {
  formatWarmupMessage,
  formatWorkspaceWarmupMessage,
  summarizeWarmupStatus,
  type WarmupSummary,
} from "./warmup.js";
import { formatActionFallbackMessage } from "./fallback.js";

function getConfiguredLanguages(): SupportedLanguage[] {
  const loaded = tryLoadConfig();
  if (!loaded.config) return [];

  return Object.entries(loaded.config.servers)
    .filter(([, serverConfig]) => serverConfig)
    .map(([language]) => language as SupportedLanguage);
}

export function detectLikelyWorkspaceLanguages(startPath: string): SupportedLanguage[] {
  const startDir = fs.realpathSync.native(startPath);

  return getConfiguredLanguages().filter((language) => {
    for (const dir of walkParents(startDir)) {
      if (ROOT_MARKERS[language].some((marker) => fs.existsSync(path.join(dir, marker)))) {
        return true;
      }
    }

    return false;
  });
}

function summarizeStatus(statuses: ServerStatus[]): string {
  if (statuses.length === 0) return "LSP: idle";

  if (statuses.length === 1) {
    const [status] = statuses;
    return `LSP: ${status.language} ${status.state}`;
  }

  const uniqueStates = Array.from(new Set(statuses.map((status) => status.state)));
  if (uniqueStates.length === 1) {
    const languages = Array.from(new Set(statuses.map((status) => status.language))).join(", ");
    return `LSP: ${statuses.length} ${uniqueStates[0]} (${languages})`;
  }

  const counts = new Map<string, number>();
  for (const status of statuses) {
    counts.set(status.state, (counts.get(status.state) ?? 0) + 1);
  }

  return `LSP: ${Array.from(counts.entries(), ([state, count]) => `${count} ${state}`).join(", ")}`;
}

function rootHintToWorkspacePath(rootHintPath: string): string {
  const stat = fs.statSync(rootHintPath);
  const workspacePath = stat.isDirectory() ? rootHintPath : path.dirname(rootHintPath);
  return fs.realpathSync.native(workspacePath);
}

function toWorkspaceNoProjectError(
  language: SupportedLanguage,
  rootHintPath: string,
  error: unknown,
): LspNoProjectError | undefined {
  if (language !== "kotlin") return undefined;
  if (!(error instanceof Error)) return undefined;
  if (!/Kotlin LSP only works in Gradle or Maven projects/.test(error.message)) return undefined;
  return new LspNoProjectError("workspace/symbol", language, rootHintToWorkspacePath(rootHintPath), "project detection");
}

export function formatStatusDetails(manager?: ServerManager): string {
  const loadedConfig = manager ? undefined : tryLoadConfig();
  return renderStatusDetails({
    statuses: manager?.getStatus() ?? [],
    configuredLanguages: manager?.getConfiguredLanguages() ?? getConfiguredLanguages(),
    configPath: CONFIG_PATH,
    configError: loadedConfig?.error,
  });
}

export function formatLogDetails(manager?: ServerManager): string {
  return renderLogDetails({
    statuses: manager?.getStatus() ?? [],
    logs: manager?.getRecentLogLines() ?? [],
    configPath: CONFIG_PATH,
  });
}

const READY_WAIT_TIMEOUT_MS = 1_500;

function updateStatus(manager: ServerManager | undefined, ctx: ExtensionContext) {
  if (!ctx.hasUI) return;
  ctx.ui.setStatus("pi-lsp", summarizeStatus(manager?.getStatus() ?? []));
}

function createWarmupToolResult(action: QueryAction, summary: WarmupSummary) {
  return {
    content: [{ type: "text", text: formatWarmupMessage(action, summary) }],
    details: {
      action,
      configPath: CONFIG_PATH,
      warmingUp: true,
      language: summary.language,
      root: summary.root,
      state: summary.state,
      elapsedMs: summary.elapsedMs,
      lastFailure: summary.lastFailure,
    },
  };
}

function createFallbackToolResult(
  action: QueryAction,
  language: SupportedLanguage,
  root: string,
  error: unknown,
) {
  return {
    content: [{ type: "text", text: formatActionFallbackMessage({ action, language, root, error }) }],
    details: {
      action,
      configPath: CONFIG_PATH,
      degraded: true,
      language,
      root,
      error: error instanceof Error ? error.message : String(error),
    },
  };
}

function isAbortError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return /abort|cancel/i.test(error.message);
}

function formatWorkspaceSymbolsUnsupportedMessage(
  unsupported: UnsupportedLspMethodError[],
  noProject: LspNoProjectError[],
  failures: string[],
): string {
  const uniqueServers = Array.from(
    new Map(
      unsupported.map((error) => [
        `${error.language}:${error.serverName}:${error.root}`,
        `${error.language} (${error.serverName})`,
      ]),
    ).values(),
  );

  const lines: string[] = [];

  if (uniqueServers.length > 0) {
    lines.push(
      uniqueServers.length === 1
        ? `workspace_symbols is not supported by the configured ${uniqueServers[0]} language server.`
        : `workspace_symbols is not supported by these configured language servers: ${uniqueServers.join(", ")}.`,
    );
  }

  if (noProject.length > 0) {
    const noProjectServers = Array.from(
      new Map(
        noProject.map((error) => [
          `${error.language}:${error.serverName}:${error.root}`,
          `${error.language} (${error.serverName})`,
        ]),
      ).values(),
    );
    lines.push(
      noProjectServers.length === 1
        ? `${noProjectServers[0]} could not answer workspace_symbols because this workspace is not a recognized project.`
        : `${noProjectServers.join(", ")} could not answer workspace_symbols because this workspace is not a recognized project.`,
    );
  }

  lines.push(
    "",
    "Recommended fallback:",
    "- use grep for repo-wide symbol-name lookup",
    "- use document_symbols for structure inside a specific file",
    "- use definition or references once you know a symbol position",
  );

  if (failures.length > 0) {
    lines.push("", `Unavailable: ${failures.join(" | ")}`);
  }

  return lines.join("\n");
}

function dedupeWorkspaceSymbols(result: any[]): any[] {
  const seen = new Set<string>();
  const deduped: any[] = [];

  for (const symbol of result) {
    const uri = symbol?.location?.uri ?? "";
    const start = symbol?.location?.range?.start;
    const key = [symbol?.name ?? "", symbol?.kind ?? "", symbol?.containerName ?? "", uri, start?.line ?? "", start?.character ?? ""].join(":");
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(symbol);
  }

  return deduped;
}

async function getReadyServerOrWarmup(
  manager: ServerManager,
  language: SupportedLanguage,
  root: string,
  action: QueryAction,
  signal: AbortSignal | undefined,
  ctx: ExtensionContext,
): Promise<{ server?: Awaited<ReturnType<ServerManager["getOrCreate"]>>; warmup?: WarmupSummary }> {
  const server = manager.startInBackground(language, root);
  updateStatus(manager, ctx);

  try {
    await server.waitUntilReady({ signal, maxWaitMs: READY_WAIT_TIMEOUT_MS, acceptIndexing: true });
    updateStatus(manager, ctx);
    return { server };
  } catch (error) {
    updateStatus(manager, ctx);
    if (isLspReadinessTimeoutError(error)) {
      return { warmup: summarizeWarmupStatus(server.getStatus()) };
    }
    if (isAbortError(error)) throw error;
    throw error;
  }
}

export default function piLspExtension(pi: ExtensionAPI) {
  let manager: ServerManager | undefined;

  const getManager = () => {
    if (!manager) manager = new ServerManager(loadConfig());
    return manager;
  };

  const getManagerIfConfigured = () => {
    try {
      return getManager();
    } catch {
      return undefined;
    }
  };

  const executeAction = async (
    action: QueryAction,
    params: {
      path?: string;
      language?: SupportedLanguage;
      line?: number;
      character?: number;
      query?: string;
      includeDeclaration?: boolean;
      maxResults?: number;
    },
    signal: AbortSignal | undefined,
    ctx: ExtensionContext,
  ) => {
    const maxResults = params.maxResults ?? 50;
    const explicitLanguage = params.language as SupportedLanguage | undefined;
    const resolvedPath = params.path ? resolveFilePath(params.path, ctx.cwd) : undefined;
    const resolvedPathIsDirectory = resolvedPath ? fs.statSync(resolvedPath).isDirectory() : false;
    const filePath = resolvedPath && !resolvedPathIsDirectory ? resolvedPath : undefined;

    if (resolvedPathIsDirectory && action !== "workspace_symbols") {
      throw new Error(`Action ${action} requires a file path, but received a directory: ${params.path}`);
    }

    const inferredLanguage = filePath ? detectLanguage(filePath, explicitLanguage) : explicitLanguage;
    const serverManager = getManager();

    if (action === "workspace_symbols") {
      if (!params.query?.trim()) throw new Error("workspace_symbols requires a non-empty query.");

      const targetLanguages = inferredLanguage
        ? [inferredLanguage]
        : (() => {
            const detectedLanguages = detectLikelyWorkspaceLanguages(resolvedPath ?? ctx.cwd);
            return detectedLanguages.length > 0 ? detectedLanguages : serverManager.getConfiguredLanguages();
          })();
      if (targetLanguages.length === 0) {
        throw new Error(`No LSP servers configured. Check ${CONFIG_PATH}.`);
      }

      const results: any[] = [];
      const failures: string[] = [];
      const unsupported: UnsupportedLspMethodError[] = [];
      const noProject: LspNoProjectError[] = [];
      const warming: WarmupSummary[] = [];

      for (const language of targetLanguages) {
        const rootHintPath = resolvedPath ?? ctx.cwd;

        try {
          const root = detectProjectRoot(rootHintPath, language, ctx.cwd);
          const ready = await getReadyServerOrWarmup(serverManager, language, root, action, signal, ctx);
          if (ready.warmup) {
            warming.push(ready.warmup);
            continue;
          }

          const result = await ready.server!.request("workspace/symbol", { query: params.query }, 20_000);
          if (Array.isArray(result)) results.push(...result);
        } catch (error) {
          const rootDetectionNoProject = toWorkspaceNoProjectError(language, rootHintPath, error);
          if (rootDetectionNoProject) {
            noProject.push(rootDetectionNoProject);
            continue;
          }

          if (isUnsupportedLspMethodError(error, "workspace/symbol")) {
            unsupported.push(error);
            continue;
          }

          if (isLspNoProjectError(error, "workspace/symbol")) {
            noProject.push(error);
            continue;
          }

          if (isAbortError(error)) throw error;

          const message = error instanceof Error ? error.message : String(error);
          failures.push(`${language}: ${message}`);
        }
      }

      updateStatus(serverManager, ctx);

      const dedupedResults = dedupeWorkspaceSymbols(results);
      if (dedupedResults.length === 0) {
        if (warming.length > 0 && unsupported.length === 0 && noProject.length === 0 && failures.length === 0) {
          return {
            content: [
              {
                type: "text",
                text: formatWorkspaceWarmupMessage(action, warming),
              },
            ],
            details: {
              action,
              configPath: CONFIG_PATH,
              languages: targetLanguages,
              path: resolvedPath,
              warmingUp: warming,
            },
          };
        }

        if (unsupported.length > 0 || noProject.length > 0) {
          const warmupText = warming.length > 0 ? `\n\n${formatWorkspaceWarmupMessage(action, warming)}` : "";
          return {
            content: [
              {
                type: "text",
                text: `${formatWorkspaceSymbolsUnsupportedMessage(unsupported, noProject, failures)}${warmupText}`,
              },
            ],
            details: {
              action,
              configPath: CONFIG_PATH,
              languages: targetLanguages,
              path: resolvedPath,
              unsupported: unsupported.map((error) => ({
                language: error.language,
                serverName: error.serverName,
                root: error.root,
                method: error.method,
              })),
              noProject: noProject.map((error) => ({
                language: error.language,
                serverName: error.serverName,
                root: error.root,
                method: error.method,
              })),
              warmingUp: warming,
              unavailable: failures,
            },
          };
        }

        if (failures.length > 0) {
          throw new Error(failures.join("\n"));
        }
      }

      let text = formatWorkspaceSymbols(dedupedResults, maxResults);
      const notes: string[] = [];
      if (unsupported.length > 0) {
        const skipped = Array.from(new Set(unsupported.map((error) => `${error.language} (${error.serverName})`)));
        notes.push(`Skipped unsupported: ${skipped.join(" | ")}`);
      }
      if (noProject.length > 0) {
        const skipped = Array.from(new Set(noProject.map((error) => `${error.language} (${error.serverName})`)));
        notes.push(`Skipped no-project workspaces: ${skipped.join(" | ")}`);
      }
      if (warming.length > 0) {
        notes.push(formatWorkspaceWarmupMessage(action, warming));
      }
      if (failures.length > 0) {
        notes.push(`Unavailable: ${failures.join(" | ")}`);
      }
      if (notes.length > 0) {
        text += `\n\n${notes.join("\n")}`;
      }

      return {
        content: [{ type: "text", text }],
        details: {
          action,
          configPath: CONFIG_PATH,
          languages: targetLanguages,
          path: resolvedPath,
          unsupported: unsupported.map((error) => ({
            language: error.language,
            serverName: error.serverName,
            root: error.root,
            method: error.method,
          })),
          noProject: noProject.map((error) => ({
            language: error.language,
            serverName: error.serverName,
            root: error.root,
            method: error.method,
          })),
          warmingUp: warming,
          unavailable: failures,
        },
      };
    }

    if (!inferredLanguage) {
      throw new Error("Could not determine language. Provide either a path or a language.");
    }

    const documentPath = ensureActionSupportsPath(action, filePath);
    const documentUri = pathToFileURL(documentPath).href;
    const root = detectProjectRoot(documentPath, inferredLanguage, ctx.cwd);
    const position =
      action === "hover" || action === "definition" || action === "references"
        ? toZeroIndexedPosition(params.line, params.character)
        : undefined;

    try {
      const ready = await getReadyServerOrWarmup(serverManager, inferredLanguage, root, action, signal, ctx);
      if (ready.warmup) {
        return createWarmupToolResult(action, ready.warmup);
      }

      const server = ready.server!;

      switch (action) {
        case "hover": {
          await server.syncDocument(documentPath);
          const result = await server.request(
            "textDocument/hover",
            {
              textDocument: toTextDocumentIdentifier(documentPath),
              position,
            },
            15_000,
          );
          updateStatus(serverManager, ctx);
          return {
            content: [{ type: "text", text: hoverToText(result) }],
            details: { action, configPath: CONFIG_PATH, language: inferredLanguage, root },
          };
        }

        case "definition": {
          await server.syncDocument(documentPath);
          const result = await server.request(
            "textDocument/definition",
            {
              textDocument: toTextDocumentIdentifier(documentPath),
              position,
            },
            20_000,
          );
          updateStatus(serverManager, ctx);
          return {
            content: [{ type: "text", text: formatLocations("Definitions", result, maxResults) }],
            details: { action, configPath: CONFIG_PATH, language: inferredLanguage, root },
          };
        }

        case "references": {
          await server.syncDocument(documentPath);
          const result = await server.request(
            "textDocument/references",
            {
              textDocument: toTextDocumentIdentifier(documentPath),
              position,
              context: {
                includeDeclaration: params.includeDeclaration ?? false,
              },
            },
            20_000,
          );
          updateStatus(serverManager, ctx);
          return {
            content: [{ type: "text", text: formatLocations("References", result, maxResults) }],
            details: { action, configPath: CONFIG_PATH, language: inferredLanguage, root },
          };
        }

        case "diagnostics": {
          const diagnostics = await server.getDiagnostics(documentPath);
          updateStatus(serverManager, ctx);
          return {
            content: [{ type: "text", text: formatDiagnostics(diagnostics, documentPath, maxResults) }],
            details: { action, configPath: CONFIG_PATH, language: inferredLanguage, root },
          };
        }

        case "document_symbols": {
          await server.syncDocument(documentPath);
          const result = await server.request(
            "textDocument/documentSymbol",
            {
              textDocument: toTextDocumentIdentifier(documentPath),
            },
            20_000,
          );
          updateStatus(serverManager, ctx);
          return {
            content: [{ type: "text", text: formatDocumentSymbols(result, documentUri, maxResults) }],
            details: { action, configPath: CONFIG_PATH, language: inferredLanguage, root },
          };
        }

        default:
          throw new Error(`Unsupported action: ${String(action)}`);
      }
    } catch (error) {
      updateStatus(serverManager, ctx);
      if (isAbortError(error)) throw error;
      return createFallbackToolResult(action, inferredLanguage, root, error);
    }
  };

  pi.registerTool({
    name: "lsp_query",
    label: "LSP Query",
    description:
      "Query language servers for TypeScript, Nix, and Kotlin. Supports hover, definition, references, diagnostics, document symbols, and workspace symbol search.",
    promptSnippet:
      "Use LSP for type information, go-to-definition, references, diagnostics, and symbol discovery in TypeScript, Nix, and Kotlin.",
    promptGuidelines: [
      "Use this tool on demand when you need semantic code intelligence such as types, definitions, references, or diagnostics.",
      "Do not assume it runs automatically after edits; call it explicitly when verification is useful.",
    ],
    parameters: LspQueryParams,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      return executeAction(params.action as QueryAction, params, signal, ctx);
    },
  });

  pi.registerTool({
    name: "workspace_symbols",
    label: "Workspace Symbols",
    description:
      "Search semantic symbols across configured language servers. Works best for functions, classes, interfaces, modules, and declarations.",
    promptSnippet: "Search semantic workspace symbols before using plain text grep for code navigation.",
    promptGuidelines: [
      "Use this before grep when you are looking for functions, classes, interfaces, modules, or declarations in supported languages.",
    ],
    parameters: WorkspaceSymbolsParams,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      return executeAction("workspace_symbols", params, signal, ctx);
    },
  });

  pi.registerTool({
    name: "document_symbols",
    label: "Document Symbols",
    description: "List semantic symbols inside a supported-language file.",
    promptSnippet: "Inspect file structure before reading large supported-language files.",
    promptGuidelines: [
      "Use this before reading a large TypeScript, Nix, or Kotlin file when you need a structural overview.",
    ],
    parameters: DocumentSymbolsParams,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      return executeAction("document_symbols", params, signal, ctx);
    },
  });

  pi.registerTool({
    name: "definition",
    label: "Definition",
    description: "Jump to the semantic definition of the symbol at a given file position.",
    promptSnippet: "Jump to symbol definitions semantically instead of searching by text.",
    promptGuidelines: [
      "Use this when you already know a symbol position and want its declaration or implementation site.",
    ],
    parameters: PositionSearchParams,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      return executeAction("definition", params, signal, ctx);
    },
  });

  pi.registerTool({
    name: "references",
    label: "References",
    description: "Find semantic references to the symbol at a given file position.",
    promptSnippet: "Find semantic symbol usages instead of grep when the target is real code.",
    promptGuidelines: [
      "Prefer this over grep when you need callers or usages of a real symbol in a supported language.",
    ],
    parameters: ReferencesParams,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      return executeAction("references", params, signal, ctx);
    },
  });

  pi.registerTool({
    name: "hover",
    label: "Hover",
    description: "Get type or symbol information at a given file position.",
    promptSnippet: "Inspect type and symbol information at a precise position.",
    promptGuidelines: [
      "Use this for signatures, inferred types, and symbol details at a known position.",
    ],
    parameters: PositionParams,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      return executeAction("hover", params, signal, ctx);
    },
  });

  pi.registerTool({
    name: "diagnostics",
    label: "Diagnostics",
    description: "Read current language-server diagnostics for a supported-language file.",
    promptSnippet: "Check language-server diagnostics after edits or when debugging compile issues.",
    promptGuidelines: [
      "Use this after code changes when you want semantic validation from the language server.",
    ],
    parameters: DiagnosticsParams,
    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      return executeAction("diagnostics", params, signal, ctx);
    },
  });

  pi.registerCommand("lsp-status", {
    description: "Show running LSP servers and configured languages",
    handler: async (_args, ctx) => {
      if (!ctx.hasUI) return;
      updateStatus(manager, ctx);
      ctx.ui.notify(formatStatusDetails(manager), "info");
    },
  });

  pi.registerCommand("lsp-restart", {
    description: "Restart all tracked LSP runtimes",
    handler: async (_args, ctx) => {
      if (!manager || manager.getStatus().length === 0) {
        updateStatus(manager, ctx);
        if (ctx.hasUI) ctx.ui.notify("No tracked LSP runtimes to restart.", "info");
        return;
      }

      await manager.restart();
      updateStatus(manager, ctx);
      if (ctx.hasUI) ctx.ui.notify("Restarted all tracked LSP runtimes.", "info");
    },
  });

  pi.registerCommand("lsp-stop", {
    description: "Stop all tracked LSP runtimes",
    handler: async (_args, ctx) => {
      if (!manager || manager.getStatus().length === 0) {
        updateStatus(manager, ctx);
        if (ctx.hasUI) ctx.ui.notify("No tracked LSP runtimes to stop.", "info");
        return;
      }

      await manager.stop();
      updateStatus(manager, ctx);
      if (ctx.hasUI) ctx.ui.notify("Stopped all tracked LSP runtimes.", "info");
    },
  });

  pi.registerCommand("lsp-log", {
    description: "Show recent LSP lifecycle and stderr log lines",
    handler: async (_args, ctx) => {
      if (!ctx.hasUI) return;
      updateStatus(manager, ctx);
      ctx.ui.notify(formatLogDetails(manager), "info");
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    const serverManager = getManagerIfConfigured();
    if (!serverManager) {
      updateStatus(manager, ctx);
      return;
    }

    const likelyLanguages = detectLikelyWorkspaceLanguages(ctx.cwd);
    for (const language of likelyLanguages) {
      try {
        const root = detectProjectRoot(ctx.cwd, language, ctx.cwd);
        const server = serverManager.warm(language, root);
        void server.waitUntilReady({ maxWaitMs: 20_000, acceptIndexing: true }).catch(() => undefined).finally(() => {
          updateStatus(serverManager, ctx);
        });
      } catch {
        // Skip warmup when the workspace is not a valid project for that language.
      }
    }

    updateStatus(serverManager, ctx);
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    if (manager) await manager.shutdown();
    manager = undefined;
    if (ctx.hasUI) ctx.ui.setStatus("pi-lsp", undefined);
  });
}
