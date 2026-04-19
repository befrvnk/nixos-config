export type SupportedLanguage = "typescript" | "nix" | "kotlin";

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

export type ServerLifecycleState =
  | "starting"
  | "initializing"
  | "indexing"
  | "ready"
  | "failed"
  | "stopped"
  | "restarting";

export type LspFailureCategory =
  | "not_configured"
  | "spawn_failed"
  | "initialize_timeout"
  | "initialize_failed"
  | "process_exited"
  | "workspace_import_failed"
  | "request_timeout"
  | "unsupported_method"
  | "no_project"
  | "outside_workspace"
  | "aborted";

export type LspFailureInfo = {
  category: LspFailureCategory;
  message: string;
  at: number;
  method?: string;
};

export type RequestMetric = {
  method: string;
  startedAt: number;
  completedAt: number;
  durationMs: number;
  ok: boolean;
  error?: string;
};

export type ServerStatus = {
  language: SupportedLanguage;
  root: string;
  pid?: number;
  state: ServerLifecycleState;
  startedAt?: number;
  initializedAt?: number;
  readyAt?: number;
  failedAt?: number;
  openDocuments: number;
  restartCount: number;
  lastFailure?: LspFailureInfo;
  lastStderrLines: string[];
  lastRequest?: RequestMetric;
};
