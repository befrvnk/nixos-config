import { StringEnum } from "@mariozechner/pi-ai";
import { Type } from "@sinclair/typebox";
import { ACTIONS, LANGUAGES } from "./constants.js";

const pathParam = Type.String({ description: "File path for document-based queries" });
const languageParam = StringEnum(LANGUAGES, {
  description: "Language override when no file path is provided",
});
const lineParam = Type.Integer({
  description: "1-indexed line number",
  minimum: 1,
});
const characterParam = Type.Integer({
  description: "1-indexed character number",
  minimum: 1,
});
const maxResultsParam = Type.Integer({
  description: "Maximum number of items to return",
  default: 50,
  minimum: 1,
});

export const LspQueryParams = Type.Object({
  action: StringEnum(ACTIONS, { description: "LSP query to run" }),
  path: Type.Optional(pathParam),
  language: Type.Optional(languageParam),
  line: Type.Optional(lineParam),
  character: Type.Optional(characterParam),
  query: Type.Optional(Type.String({ description: "Symbol search query for workspace_symbols" })),
  includeDeclaration: Type.Optional(
    Type.Boolean({
      description: "Include the symbol declaration when returning references",
      default: false,
    }),
  ),
  maxResults: Type.Optional(maxResultsParam),
});

export const WorkspaceSymbolsParams = Type.Object({
  query: Type.String({ description: "Workspace symbol search query" }),
  path: Type.Optional(Type.String({ description: "Optional file or directory used to infer project root and language" })),
  language: Type.Optional(languageParam),
  maxResults: Type.Optional(maxResultsParam),
});

export const DocumentSymbolsParams = Type.Object({
  path: pathParam,
  maxResults: Type.Optional(maxResultsParam),
});

export const PositionParams = Type.Object({
  path: pathParam,
  line: lineParam,
  character: characterParam,
});

export const PositionSearchParams = Type.Object({
  path: pathParam,
  line: lineParam,
  character: characterParam,
  maxResults: Type.Optional(maxResultsParam),
});

export const ReferencesParams = Type.Object({
  path: pathParam,
  line: lineParam,
  character: characterParam,
  includeDeclaration: Type.Optional(
    Type.Boolean({
      description: "Include the declaration in the returned references",
      default: false,
    }),
  ),
  maxResults: Type.Optional(maxResultsParam),
});

export const DiagnosticsParams = Type.Object({
  path: pathParam,
  maxResults: Type.Optional(maxResultsParam),
});
