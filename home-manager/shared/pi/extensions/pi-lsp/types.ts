export type SupportedLanguage = "typescript" | "nix" | "kotlin" | "java";

export type QueryAction =
  | "hover"
  | "definition"
  | "references"
  | "diagnostics"
  | "document_symbols"
  | "workspace_symbols";

export type MarkupContent = {
  kind?: string;
  value?: string;
};

export type Position = {
  line: number;
  character: number;
};

export type Range = {
  start: Position;
  end: Position;
};

export type Location = {
  uri: string;
  range: Range;
};

export type LocationLink = {
  targetUri: string;
  targetSelectionRange?: Range;
  targetRange?: Range;
};

export type Diagnostic = {
  range: Range;
  severity?: number;
  code?: string | number;
  message: string;
  source?: string;
};

export type SymbolLike = {
  name?: string;
  kind?: number;
  location?: Location;
  range?: Range;
  selectionRange?: Range;
  children?: SymbolLike[];
  containerName?: string;
};

export type ServerConfig = {
  command: string;
  args?: string[];
  startupTimeoutMs?: number;
};

export type ExtensionConfig = {
  servers: Partial<Record<SupportedLanguage, ServerConfig>>;
};

export type OpenDocument = {
  version: number;
  text: string;
};
