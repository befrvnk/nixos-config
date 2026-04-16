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
  isUnsupportedLspMethodError,
  ServerManager,
  type LspNoProjectError,
  type UnsupportedLspMethodError,
} from "./server.js";
import { formatStatusDetails as renderStatusDetails } from "./status.js";
import type { QueryAction, ServerStatus, SupportedLanguage } from "./types.js";

function getConfiguredLanguages(): SupportedLanguage[] {
  const loaded = tryLoadConfig();
  if (!loaded.config) return [];

  return Object.entries(loaded.config.servers)
    .filter(([, serverConfig]) => serverConfig)
    .map(([language]) => language as SupportedLanguage);
}

function detectLikelyWorkspaceLanguages(startPath: string): SupportedLanguage[] {
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

  const languages = Array.from(new Set(statuses.map((status) => status.language))).join(", ");
  return `LSP: ${statuses.length} active (${languages})`;
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

function updateStatus(manager: ServerManager | undefined, ctx: ExtensionContext) {
  if (!ctx.hasUI) return;
  ctx.ui.setStatus("pi-lsp", summarizeStatus(manager?.getStatus() ?? []));
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

export default function piLspExtension(pi: ExtensionAPI) {
  let manager: ServerManager | undefined;

  const getManager = () => {
    if (!manager) manager = new ServerManager(loadConfig());
    return manager;
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

      for (const language of targetLanguages) {
        const rootHintPath = resolvedPath ?? ctx.cwd;
        const root = detectProjectRoot(rootHintPath, language, ctx.cwd);

        try {
          const server = await serverManager.get(language, root);
          const result = await server.request("workspace/symbol", { query: params.query }, 20_000);
          if (Array.isArray(result)) results.push(...result);
        } catch (error) {
          if (isUnsupportedLspMethodError(error, "workspace/symbol")) {
            unsupported.push(error);
            continue;
          }

          if (isLspNoProjectError(error, "workspace/symbol")) {
            noProject.push(error);
            continue;
          }

          const message = error instanceof Error ? error.message : String(error);
          failures.push(`${language}: ${message}`);
        }
      }

      updateStatus(serverManager, ctx);

      const dedupedResults = dedupeWorkspaceSymbols(results);
      if (dedupedResults.length === 0) {
        if (unsupported.length > 0 || noProject.length > 0) {
          return {
            content: [
              {
                type: "text",
                text: formatWorkspaceSymbolsUnsupportedMessage(unsupported, noProject, failures),
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
    const server = await serverManager.get(inferredLanguage, root);

    switch (action) {
      case "hover": {
        await server.syncDocument(documentPath);
        const result = await server.request(
          "textDocument/hover",
          {
            textDocument: toTextDocumentIdentifier(documentPath),
            position: toZeroIndexedPosition(params.line, params.character),
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
            position: toZeroIndexedPosition(params.line, params.character),
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
            position: toZeroIndexedPosition(params.line, params.character),
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
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      return executeAction(params.action as QueryAction, params, ctx);
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
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      return executeAction("workspace_symbols", params, ctx);
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
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      return executeAction("document_symbols", params, ctx);
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
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      return executeAction("definition", params, ctx);
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
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      return executeAction("references", params, ctx);
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
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      return executeAction("hover", params, ctx);
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
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      return executeAction("diagnostics", params, ctx);
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
    description: "Stop all running LSP servers; they restart lazily on next use",
    handler: async (_args, ctx) => {
      if (manager) {
        await manager.shutdown();
        manager = undefined;
      }
      updateStatus(manager, ctx);
      if (ctx.hasUI) {
        ctx.ui.notify("Stopped all running LSP servers. They will start lazily on next use.", "info");
      }
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    updateStatus(manager, ctx);
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    if (manager) await manager.shutdown();
    manager = undefined;
    if (ctx.hasUI) ctx.ui.setStatus("pi-lsp", undefined);
  });
}
