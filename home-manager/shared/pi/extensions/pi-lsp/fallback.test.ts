import test from "node:test";
import assert from "node:assert/strict";
import { formatActionFallbackMessage } from "./fallback.ts";

test("formatActionFallbackMessage renders actionable degraded responses", () => {
  const definition = formatActionFallbackMessage({
    action: "definition",
    language: "kotlin",
    root: "/repo",
    error: new Error("Timed out waiting for textDocument/definition from kotlin"),
  });

  assert.match(definition, /kotlin LSP is unavailable for definition/);
  assert.match(definition, /Reason: request_timeout:/);
  assert.match(definition, /use grep to search for the symbol name/);

  const diagnostics = formatActionFallbackMessage({
    action: "diagnostics",
    language: "kotlin",
    root: "/repo",
    error: new Error("LSP server exited for kotlin/"),
  });

  assert.match(diagnostics, /diagnostics/);
  assert.match(diagnostics, /verify with the project build or compile command/);

  const documentSymbols = formatActionFallbackMessage({
    action: "document_symbols",
    language: "typescript",
    root: "/repo-web",
    error: new Error("Failed to start LSP server for typescript"),
  });

  assert.match(documentSymbols, /read the file directly for structure/);
});
