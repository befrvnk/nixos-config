import { classifyLspFailure } from "./server.js";
import type { QueryAction, SupportedLanguage } from "./types.js";

export function formatActionFallbackMessage(options: {
  action: QueryAction;
  language: SupportedLanguage;
  root: string;
  error: unknown;
}): string {
  const { action, language, root, error } = options;
  const failure = classifyLspFailure(error, {
    method:
      action === "hover"
        ? "textDocument/hover"
        : action === "definition"
          ? "textDocument/definition"
          : action === "references"
            ? "textDocument/references"
            : action === "document_symbols"
              ? "textDocument/documentSymbol"
              : action === "diagnostics"
                ? "textDocument/publishDiagnostics"
                : undefined,
  });

  const lines = [
    `${language} LSP is unavailable for ${action}.`,
    `Root: ${root}`,
    `Reason: ${failure.category}: ${failure.message}`,
    "",
    ...getSuggestions(action),
  ];

  return lines.join("\n");
}

function getSuggestions(action: QueryAction): string[] {
  switch (action) {
    case "definition":
      return [
        "Suggested fallback:",
        "- use grep to search for the symbol name",
        "- use workspace_symbols when semantic search becomes available",
        "- retry after warmup or run /lsp-status",
      ];

    case "references":
      return [
        "Suggested fallback:",
        "- use grep to search for call sites or symbol names",
        "- retry after warmup or run /lsp-status",
      ];

    case "document_symbols":
      return [
        "Suggested fallback:",
        "- read the file directly for structure",
        "- retry after warmup or run /lsp-status",
      ];

    case "diagnostics":
      return [
        "Suggested fallback:",
        "- verify with the project build or compile command",
        "- retry after warmup or run /lsp-status",
      ];

    case "hover":
      return [
        "Suggested fallback:",
        "- retry after warmup or run /lsp-status",
        "- use definition to jump to the declaration if available later",
      ];

    case "workspace_symbols":
      return [
        "Suggested fallback:",
        "- use grep for repo-wide symbol-name lookup",
        "- retry after warmup or run /lsp-status",
      ];
  }
}
