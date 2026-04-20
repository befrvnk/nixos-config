import { ACTIONS, LANGUAGES } from "./constants.js";

type JsonSchema = Record<string, unknown>;

function stringEnum(values: readonly string[], options: JsonSchema = {}): JsonSchema {
  return {
    type: "string",
    enum: [...values],
    ...options,
  };
}

function objectSchema(
  properties: Record<string, JsonSchema>,
  required: string[],
): JsonSchema {
  return {
    type: "object",
    properties,
    required,
    additionalProperties: false,
  };
}

const pathParam = { type: "string", description: "File path for document-based queries" };
const languageParam = stringEnum(LANGUAGES, {
  description: "Language override when no file path is provided",
});
const lineParam = {
  type: "integer",
  description: "1-indexed line number",
  minimum: 1,
};
const characterParam = {
  type: "integer",
  description: "1-indexed character number",
  minimum: 1,
};
const maxResultsParam = {
  type: "integer",
  description: "Maximum number of items to return",
  default: 50,
  minimum: 1,
};

export const LspQueryParams = objectSchema(
  {
    action: stringEnum(ACTIONS, { description: "LSP query to run" }),
    path: pathParam,
    language: languageParam,
    line: lineParam,
    character: characterParam,
    query: { type: "string", description: "Symbol search query for workspace_symbols" },
    includeDeclaration: {
      type: "boolean",
      description: "Include the symbol declaration when returning references",
      default: false,
    },
    maxResults: maxResultsParam,
  },
  ["action"],
);

export const WorkspaceSymbolsParams = objectSchema(
  {
    query: { type: "string", description: "Workspace symbol search query" },
    path: {
      type: "string",
      description: "Optional file or directory used to infer project root and language",
    },
    language: languageParam,
    maxResults: maxResultsParam,
  },
  ["query"],
);

export const DocumentSymbolsParams = objectSchema(
  {
    path: pathParam,
    maxResults: maxResultsParam,
  },
  ["path"],
);

export const PositionParams = objectSchema(
  {
    path: pathParam,
    line: lineParam,
    character: characterParam,
  },
  ["path", "line", "character"],
);

export const PositionSearchParams = objectSchema(
  {
    path: pathParam,
    line: lineParam,
    character: characterParam,
    maxResults: maxResultsParam,
  },
  ["path", "line", "character"],
);

export const ReferencesParams = objectSchema(
  {
    path: pathParam,
    line: lineParam,
    character: characterParam,
    includeDeclaration: {
      type: "boolean",
      description: "Include the declaration in the returned references",
      default: false,
    },
    maxResults: maxResultsParam,
  },
  ["path", "line", "character"],
);

export const DiagnosticsParams = objectSchema(
  {
    path: pathParam,
    maxResults: maxResultsParam,
  },
  ["path"],
);
