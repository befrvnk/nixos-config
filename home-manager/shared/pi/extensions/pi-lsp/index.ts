import { pathToFileURL } from "node:url";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { CONFIG_PATH, loadConfig } from "./config.js";
import {
  formatDiagnostics,
  formatDocumentSymbols,
  formatLocations,
  formatWorkspaceSymbols,
  hoverToText,
} from "./formatting.js";
import {
  detectLanguage,
  detectProjectRoot,
  ensureActionSupportsPath,
  resolveFilePath,
  toTextDocumentIdentifier,
  toZeroIndexedPosition,
} from "./paths.js";
import { LspQueryParams } from "./schemas.js";
import { ServerManager } from "./server.js";
import type { QueryAction, SupportedLanguage } from "./types.js";

export default function piLspExtension(pi: ExtensionAPI) {
  let manager: ServerManager | undefined;

  const getManager = () => {
    if (!manager) manager = new ServerManager(loadConfig());
    return manager;
  };

  pi.registerTool({
    name: "lsp_query",
    label: "LSP Query",
    description:
      "Query language servers for TypeScript, Nix, Kotlin, and Java. Supports hover, definition, references, diagnostics, document symbols, and workspace symbol search.",
    promptSnippet:
      "Use LSP for type information, go-to-definition, references, diagnostics, and symbol discovery in TypeScript, Nix, Kotlin, and Java.",
    promptGuidelines: [
      "Use this tool on demand when you need semantic code intelligence such as types, definitions, references, or diagnostics.",
      "Do not assume it runs automatically after edits; call it explicitly when verification is useful.",
    ],
    parameters: LspQueryParams,
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const maxResults = params.maxResults ?? 50;
      const explicitLanguage = params.language as SupportedLanguage | undefined;
      const filePath = params.path ? resolveFilePath(params.path, ctx.cwd) : undefined;
      const language = filePath ? detectLanguage(filePath, explicitLanguage) : explicitLanguage;
      if (!language) {
        throw new Error("Could not determine language. Provide either a path or a language.");
      }

      const rootHintPath = filePath ?? ctx.cwd;
      const root = detectProjectRoot(rootHintPath, language, ctx.cwd);
      const server = await getManager().get(language, root);

      if (params.action === "workspace_symbols") {
        if (!params.query?.trim()) throw new Error("workspace_symbols requires a non-empty query.");
        const result = await server.request("workspace/symbol", { query: params.query }, 20_000);
        return {
          content: [{ type: "text", text: formatWorkspaceSymbols(result, maxResults) }],
          details: { action: params.action, configPath: CONFIG_PATH, language, root },
        };
      }

      const documentPath = ensureActionSupportsPath(params.action as QueryAction, filePath);
      const documentUri = pathToFileURL(documentPath).href;

      switch (params.action) {
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
          return {
            content: [{ type: "text", text: hoverToText(result) }],
            details: { action: params.action, configPath: CONFIG_PATH, language, root },
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
          return {
            content: [{ type: "text", text: formatLocations("Definitions", result, maxResults) }],
            details: { action: params.action, configPath: CONFIG_PATH, language, root },
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
          return {
            content: [{ type: "text", text: formatLocations("References", result, maxResults) }],
            details: { action: params.action, configPath: CONFIG_PATH, language, root },
          };
        }

        case "diagnostics": {
          const diagnostics = await server.getDiagnostics(documentPath);
          return {
            content: [{ type: "text", text: formatDiagnostics(diagnostics, documentPath, maxResults) }],
            details: { action: params.action, configPath: CONFIG_PATH, language, root },
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
          return {
            content: [{ type: "text", text: formatDocumentSymbols(result, documentUri, maxResults) }],
            details: { action: params.action, configPath: CONFIG_PATH, language, root },
          };
        }

        default:
          throw new Error(`Unsupported action: ${String(params.action)}`);
      }
    },
  });

  pi.on("session_shutdown", async () => {
    if (manager) await manager.shutdown();
  });
}
