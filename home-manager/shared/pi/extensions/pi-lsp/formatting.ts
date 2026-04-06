import fs from "node:fs";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { DIAGNOSTIC_SEVERITY, SYMBOL_KINDS } from "./constants.js";
import type { Diagnostic, Location, LocationLink, MarkupContent, Range, SymbolLike } from "./types.js";

export function formatRange(range: Range | undefined): string {
  if (!range) return "unknown";
  return `${range.start.line + 1}:${range.start.character + 1}-${range.end.line + 1}:${range.end.character + 1}`;
}

export function formatLocationUri(uri: string): string {
  const filePath = fileURLToPath(uri);
  const home = os.homedir();
  return filePath.startsWith(home) ? `~${filePath.slice(home.length)}` : filePath;
}

export function previewAtLocation(uri: string, range: Range | undefined): string {
  if (!range) return "";
  try {
    const filePath = fileURLToPath(uri);
    const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
    return (lines[range.start.line] ?? "").trim();
  } catch {
    return "";
  }
}

export function renderMarkup(value: unknown): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return value.map((item) => renderMarkup(item)).filter(Boolean).join("\n\n");
  if (value && typeof value === "object") {
    const markup = value as MarkupContent & { language?: string; value?: string };
    if (typeof markup.value === "string") return markup.value;
    if (typeof markup.language === "string" && typeof markup.value === "string") {
      return `\`\`\`${markup.language}\n${markup.value}\n\`\`\``;
    }
  }
  return "";
}

export function hoverToText(result: any): string {
  if (!result?.contents) return "No hover information available.";
  return renderMarkup(result.contents).trim() || "No hover information available.";
}

export function normalizeLocations(result: Location | LocationLink | Array<Location | LocationLink> | null | undefined): Array<{
  uri: string;
  range: Range | undefined;
}> {
  if (!result) return [];
  const items = Array.isArray(result) ? result : [result];
  return items.map((item) => {
    if ("targetUri" in item) {
      return {
        uri: item.targetUri,
        range: item.targetSelectionRange ?? item.targetRange,
      };
    }
    return {
      uri: item.uri,
      range: item.range,
    };
  });
}

export function formatLocations(
  title: string,
  result: Location | LocationLink | Array<Location | LocationLink> | null | undefined,
  maxResults: number,
): string {
  const items = normalizeLocations(result);
  if (items.length === 0) return `${title}: none`;

  const lines = items.slice(0, maxResults).map((item, index) => {
    const preview = previewAtLocation(item.uri, item.range);
    const suffix = preview ? ` — ${preview}` : "";
    return `${index + 1}. ${formatLocationUri(item.uri)}:${formatRange(item.range)}${suffix}`;
  });

  if (items.length > maxResults) lines.push(`… ${items.length - maxResults} more result(s)`);
  return `${title}:\n${lines.join("\n")}`;
}

function flattenDocumentSymbols(symbols: SymbolLike[], fileUri: string, parentName?: string): Array<{
  name: string;
  kind: string;
  location: string;
}> {
  const flattened: Array<{ name: string; kind: string; location: string }> = [];

  for (const symbol of symbols) {
    const displayName = parentName ? `${parentName}.${symbol.name ?? "(anonymous)"}` : (symbol.name ?? "(anonymous)");
    const range = symbol.selectionRange ?? symbol.range ?? symbol.location?.range;
    const uri = symbol.location?.uri ?? fileUri;
    flattened.push({
      kind: SYMBOL_KINDS[symbol.kind ?? 0] ?? `Kind ${symbol.kind ?? 0}`,
      location: `${formatLocationUri(uri)}:${formatRange(range)}`,
      name: displayName,
    });
    if (Array.isArray(symbol.children) && symbol.children.length > 0) {
      flattened.push(...flattenDocumentSymbols(symbol.children, uri, displayName));
    }
  }

  return flattened;
}

export function formatDocumentSymbols(result: SymbolLike[] | null | undefined, fileUri: string, maxResults: number): string {
  if (!Array.isArray(result) || result.length === 0) return "Document symbols: none";

  const flattened = flattenDocumentSymbols(result, fileUri);
  const lines = flattened.slice(0, maxResults).map((symbol, index) => {
    return `${index + 1}. [${symbol.kind}] ${symbol.name} — ${symbol.location}`;
  });

  if (flattened.length > maxResults) lines.push(`… ${flattened.length - maxResults} more symbol(s)`);
  return `Document symbols:\n${lines.join("\n")}`;
}

export function formatWorkspaceSymbols(result: SymbolLike[] | null | undefined, maxResults: number): string {
  if (!Array.isArray(result) || result.length === 0) return "Workspace symbols: none";

  const lines = result.slice(0, maxResults).map((symbol, index) => {
    const location = symbol.location
      ? `${formatLocationUri(symbol.location.uri)}:${formatRange(symbol.location.range)}`
      : "unknown";
    const kind = SYMBOL_KINDS[symbol.kind ?? 0] ?? `Kind ${symbol.kind ?? 0}`;
    const container = symbol.containerName ? ` (${symbol.containerName})` : "";
    return `${index + 1}. [${kind}] ${symbol.name ?? "(anonymous)"}${container} — ${location}`;
  });

  if (result.length > maxResults) lines.push(`… ${result.length - maxResults} more symbol(s)`);
  return `Workspace symbols:\n${lines.join("\n")}`;
}

export function formatDiagnostics(diagnostics: Diagnostic[], filePath: string, maxResults: number): string {
  if (diagnostics.length === 0) return `Diagnostics for ${filePath}: none`;

  const lines = diagnostics.slice(0, maxResults).map((diagnostic, index) => {
    const severity = DIAGNOSTIC_SEVERITY[diagnostic.severity ?? 0] ?? "Unknown";
    const code = diagnostic.code !== undefined ? ` [${diagnostic.code}]` : "";
    const source = diagnostic.source ? ` (${diagnostic.source})` : "";
    return `${index + 1}. ${severity}${code} at ${formatRange(diagnostic.range)}${source} — ${diagnostic.message}`;
  });

  if (diagnostics.length > maxResults) lines.push(`… ${diagnostics.length - maxResults} more diagnostic(s)`);
  return `Diagnostics for ${filePath}:\n${lines.join("\n")}`;
}
