import { StringEnum } from "@mariozechner/pi-ai";
import { Type } from "@sinclair/typebox";
import { ACTIONS, LANGUAGES } from "./constants.js";

export const LspQueryParams = Type.Object({
  action: StringEnum(ACTIONS, { description: "LSP query to run" }),
  path: Type.Optional(Type.String({ description: "File path for document-based queries" })),
  language: Type.Optional(StringEnum(LANGUAGES, { description: "Language override when no file path is provided" })),
  line: Type.Optional(Type.Integer({ description: "1-indexed line number for hover/definition/references", minimum: 1 })),
  character: Type.Optional(Type.Integer({ description: "1-indexed character number for hover/definition/references", minimum: 1 })),
  query: Type.Optional(Type.String({ description: "Symbol search query for workspace_symbols" })),
  includeDeclaration: Type.Optional(
    Type.Boolean({
      description: "Include the symbol declaration when returning references",
      default: false,
    }),
  ),
  maxResults: Type.Optional(Type.Integer({ description: "Maximum number of items to return", default: 50, minimum: 1 })),
});
