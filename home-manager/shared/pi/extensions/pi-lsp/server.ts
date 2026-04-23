import { execFileSync, spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { LANGUAGE_IDS } from "./constants.js";
import type {
  Diagnostic,
  ExtensionConfig,
  LspFailureCategory,
  LspFailureInfo,
  OpenDocument,
  RequestMetric,
  ServerConfig,
  ServerLifecycleState,
  ServerStatus,
  SupportedLanguage,
} from "./types.js";

const DEFAULT_DIAGNOSTICS_TIMEOUT_MS = 5_000;
const DEFAULT_REQUEST_TIMEOUT_MS = 15_000;
const DEFAULT_KOTLIN_READY_WITHOUT_PROGRESS_MS = 5_000;
const DEFAULT_KOTLIN_STALLED_PROGRESS_TIMEOUT_MS = 30_000;
const MAX_RECENT_STDERR_LINES = 20;
const MAX_RECENT_LOG_LINES = 50;

type PendingRequest = {
  method: string;
  resolve: (value: any) => void;
  reject: (error: Error) => void;
};

type DiagnosticEntry = {
  diagnostics: Diagnostic[];
  version?: number;
  updatedAt: number;
};

type DiagnosticsWaiter = {
  requestedAt: number;
  targetVersion: number;
  resolve: (diagnostics: Diagnostic[]) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
};

type WorkDoneProgressValue = {
  kind?: string;
  title?: string;
  message?: string;
  percentage?: number;
};

export class JsonRpcStreamParser {
  private buffer = Buffer.alloc(0);

  push(chunk: Buffer): any[] {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    const messages: any[] = [];

    while (true) {
      const headerEnd = this.buffer.indexOf("\r\n\r\n");
      if (headerEnd === -1) break;

      const headerText = this.buffer.subarray(0, headerEnd).toString("utf8");
      const contentLengthMatch = headerText.match(/Content-Length:\s*(\d+)/i);
      if (!contentLengthMatch) {
        this.buffer = this.buffer.subarray(headerEnd + 4);
        continue;
      }

      const contentLength = Number(contentLengthMatch[1]);
      const bodyStart = headerEnd + 4;
      const bodyEnd = bodyStart + contentLength;
      if (this.buffer.length < bodyEnd) break;

      const body = this.buffer.subarray(bodyStart, bodyEnd).toString("utf8");
      this.buffer = this.buffer.subarray(bodyEnd);

      try {
        messages.push(JSON.parse(body));
      } catch {
        // Ignore malformed payloads.
      }
    }

    return messages;
  }
}

function formatExitSuffix(code: number | null, signal: NodeJS.Signals | null): string {
  const parts: string[] = [];
  if (typeof code === "number") parts.push(`code ${code}`);
  if (signal) parts.push(`signal ${signal}`);
  return parts.length > 0 ? ` (${parts.join(", ")})` : "";
}

function getServerLabel(command: string): string {
  return path.basename(command) || command;
}

function findExistingCommand(candidates: string[]): string | undefined {
  return candidates.find((candidate) => {
    if (candidate.includes(path.sep)) return fs.existsSync(candidate);
    return true;
  });
}

function isKotlinLspCommand(command: string): boolean {
  return /kotlinLspServerKt|(^|\s)kotlin-lsp(\s|$)/.test(command);
}

function listKotlinLspPidsFromProc(): number[] {
  try {
    return fs.readdirSync("/proc", { withFileTypes: true }).flatMap((entry) => {
      if (!entry.isDirectory() || !/^\d+$/.test(entry.name)) return [];

      try {
        const pid = Number(entry.name);
        const command = fs.readFileSync(`/proc/${entry.name}/cmdline`, "utf8").replace(/\0/g, " ").trim();
        if (!Number.isInteger(pid) || !command || !isKotlinLspCommand(command)) return [];
        return [pid];
      } catch {
        return [];
      }
    });
  } catch {
    return [];
  }
}

function listKotlinLspPids(): number[] {
  if (process.platform === "linux" && fs.existsSync("/proc")) {
    return listKotlinLspPidsFromProc();
  }

  const psCommand = findExistingCommand([
    "/run/current-system/sw/bin/ps",
    "/usr/bin/ps",
    "/bin/ps",
    "ps",
  ]);
  if (!psCommand) return [];

  try {
    const output = execFileSync(psCommand, ["-axo", "pid=,command="], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });

    return output
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line.length > 0)
      .flatMap((line) => {
        const match = line.match(/^(\d+)\s+(.*)$/);
        if (!match) return [];

        const pid = Number(match[1]);
        const command = match[2];
        if (!Number.isInteger(pid) || !isKotlinLspCommand(command)) return [];
        return [pid];
      });
  } catch {
    return [];
  }
}

function getProcessCwd(pid: number): string | undefined {
  if (process.platform === "linux") {
    try {
      return fs.realpathSync.native(fs.readlinkSync(`/proc/${pid}/cwd`));
    } catch {
      // Fall back to lsof below when procfs is unavailable.
    }
  }

  const lsofCommand = findExistingCommand([
    "/usr/sbin/lsof",
    "/usr/bin/lsof",
    "lsof",
  ]);
  if (!lsofCommand) return undefined;

  try {
    const output = execFileSync(lsofCommand, ["-a", "-p", String(pid), "-d", "cwd", "-Fn"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });

    for (const line of output.split(/\r?\n/)) {
      if (!line.startsWith("n")) continue;
      const cwd = line.slice(1).trim();
      if (!cwd) continue;
      return fs.realpathSync.native(cwd);
    }
  } catch {
    return undefined;
  }

  return undefined;
}

function findCompetingKotlinWorkspacePids(root: string, currentPid?: number): number[] {
  let normalizedRoot: string;
  try {
    normalizedRoot = fs.realpathSync.native(root);
  } catch {
    return [];
  }

  return listKotlinLspPids().filter((pid) => {
    if (pid === currentPid) return false;
    return getProcessCwd(pid) === normalizedRoot;
  });
}

function formatKotlinWorkspaceSessionConflictMessage(root: string | undefined, pids: number[]): string {
  const rootLine = root ? ` Workspace: ${root}.` : "";

  if (pids.length > 0) {
    return `Another kotlin-lsp session is already attached to this workspace.${rootLine} Competing PID(s): ${pids.join(", ")}. kotlin-lsp currently supports only one editing session per workspace root. Stop the other session or use a separate worktree, then retry.`;
  }

  return `Kotlin initialize was cancelled.${rootLine} kotlin-lsp may reject a second client for the same workspace with “Multiple editing sessions for one workspace are not supported yet”. Stop the other Kotlin LSP session for this workspace or use a separate worktree, then retry.`;
}

function pushBounded(items: string[], value: string, maxItems: number): void {
  items.push(value);
  if (items.length > maxItems) items.splice(0, items.length - maxItems);
}

function timestampPrefix(timestamp: number): string {
  return new Date(timestamp).toISOString();
}

function toError(error: unknown): Error {
  return error instanceof Error ? error : new Error(String(error));
}

function normalizeProgressToken(token: unknown): string | undefined {
  if (typeof token === "string" || typeof token === "number") return String(token);
  return undefined;
}

function summarizeProgress(value: WorkDoneProgressValue | undefined): string | undefined {
  if (!value) return undefined;

  const parts: string[] = [];
  if (typeof value.title === "string" && value.title.trim()) parts.push(value.title.trim());
  if (typeof value.message === "string" && value.message.trim()) parts.push(value.message.trim());
  if (typeof value.percentage === "number") parts.push(`${value.percentage}%`);
  return parts.length > 0 ? parts.join(" — ") : undefined;
}

function isJsonRpcRequestId(value: unknown): value is number | string {
  return typeof value === "number" || typeof value === "string";
}

function createFailureInfo(
  category: LspFailureCategory,
  message: string,
  options: { at?: number; method?: string } = {},
): LspFailureInfo {
  return {
    category,
    message,
    at: options.at ?? Date.now(),
    method: options.method,
  };
}

export function isMethodNotSupportedResponse(_method: string, error: unknown): boolean {
  if (!error || typeof error !== "object") return false;

  const payload = error as { code?: unknown; message?: unknown; data?: unknown };
  const message = typeof payload.message === "string" ? payload.message : "";
  const data = typeof payload.data === "string" ? payload.data : "";
  const combined = `${message}\n${data}`.toLowerCase();

  if (payload.code === -32601) return true;
  if (combined.includes("method not found")) return true;
  if (combined.includes("no such method")) return true;
  return false;
}

export class UnsupportedLspMethodError extends Error {
  readonly method: string;
  readonly language: SupportedLanguage;
  readonly root: string;
  readonly serverName: string;

  constructor(method: string, language: SupportedLanguage, root: string, serverName: string) {
    super(`${language}: ${serverName} does not support ${method}`);
    this.name = "UnsupportedLspMethodError";
    this.method = method;
    this.language = language;
    this.root = root;
    this.serverName = serverName;
  }
}

export function isUnsupportedLspMethodError(error: unknown, method?: string): error is UnsupportedLspMethodError {
  if (!(error instanceof UnsupportedLspMethodError)) return false;
  return method ? error.method === method : true;
}

export function isNoProjectResponse(method: string, error: unknown): boolean {
  if (method !== "workspace/symbol" || !error || typeof error !== "object") return false;

  const payload = error as { message?: unknown; data?: unknown };
  const message = typeof payload.message === "string" ? payload.message : "";
  const data = typeof payload.data === "string" ? payload.data : "";
  const combined = `${message}\n${data}`.toLowerCase();
  return combined.includes("no project");
}

export class LspNoProjectError extends Error {
  readonly method: string;
  readonly language: SupportedLanguage;
  readonly root: string;
  readonly serverName: string;

  constructor(method: string, language: SupportedLanguage, root: string, serverName: string) {
    super(`${language}: ${serverName} has no project for ${method}`);
    this.name = "LspNoProjectError";
    this.method = method;
    this.language = language;
    this.root = root;
    this.serverName = serverName;
  }
}

export function isLspNoProjectError(error: unknown, method?: string): error is LspNoProjectError {
  if (!(error instanceof LspNoProjectError)) return false;
  return method ? error.method === method : true;
}

export class LspReadinessTimeoutError extends Error {
  readonly language: SupportedLanguage;
  readonly root: string;
  readonly state: ServerLifecycleState;
  readonly maxWaitMs: number;

  constructor(language: SupportedLanguage, root: string, state: ServerLifecycleState, maxWaitMs: number) {
    super(`LSP server is still warming up for ${language} (${root}) after ${maxWaitMs}ms`);
    this.name = "LspReadinessTimeoutError";
    this.language = language;
    this.root = root;
    this.state = state;
    this.maxWaitMs = maxWaitMs;
  }
}

export function isLspReadinessTimeoutError(error: unknown): error is LspReadinessTimeoutError {
  return error instanceof LspReadinessTimeoutError;
}

export class KotlinWorkspaceSessionConflictError extends Error {
  readonly method: string;
  readonly language: SupportedLanguage;
  readonly root: string;
  readonly serverName: string;
  readonly competingPids: number[];

  constructor(
    method: string,
    language: SupportedLanguage,
    root: string,
    serverName: string,
    competingPids: number[] = [],
  ) {
    super(formatKotlinWorkspaceSessionConflictMessage(root, competingPids));
    this.name = "KotlinWorkspaceSessionConflictError";
    this.method = method;
    this.language = language;
    this.root = root;
    this.serverName = serverName;
    this.competingPids = [...competingPids];
  }
}

export function isKotlinWorkspaceSessionConflictError(
  error: unknown,
  method?: string,
): error is KotlinWorkspaceSessionConflictError {
  if (!(error instanceof KotlinWorkspaceSessionConflictError)) return false;
  return method ? error.method === method : true;
}

export function classifyLspFailure(
  error: unknown,
  options: {
    method?: string;
    language?: SupportedLanguage;
    root?: string;
    currentPid?: number;
  } = {},
): LspFailureInfo {
  if (error instanceof UnsupportedLspMethodError) {
    return createFailureInfo("unsupported_method", error.message, {
      at: Date.now(),
      method: error.method,
    });
  }

  if (error instanceof LspNoProjectError) {
    return createFailureInfo("no_project", error.message, {
      at: Date.now(),
      method: error.method,
    });
  }

  if (error instanceof KotlinWorkspaceSessionConflictError) {
    return createFailureInfo("workspace_session_conflict", error.message, {
      at: Date.now(),
      method: error.method,
    });
  }

  const normalized = toError(error);
  const message = normalized.message;
  const lowered = message.toLowerCase();
  const isExplicitWorkspaceConflict = lowered.includes("multiple editing sessions for one workspace");
  const isLikelyKotlinWorkspaceConflict = options.language === "kotlin" && lowered === "cancelled";

  if (isExplicitWorkspaceConflict || isLikelyKotlinWorkspaceConflict) {
    const competingWorkspacePids = options.root
      ? findCompetingKotlinWorkspacePids(options.root, options.currentPid)
      : [];

    if (isExplicitWorkspaceConflict || competingWorkspacePids.length > 0) {
      return createFailureInfo(
        "workspace_session_conflict",
        formatKotlinWorkspaceSessionConflictMessage(options.root, competingWorkspacePids),
        { method: options.method },
      );
    }

    if (options.method === "initialize") {
      return createFailureInfo("initialize_failed", formatKotlinWorkspaceSessionConflictMessage(options.root, []), {
        method: options.method,
      });
    }
  }

  if (lowered.includes("timed out waiting for initialize")) {
    return createFailureInfo("initialize_timeout", message, { method: "initialize" });
  }

  if (lowered.includes("timed out waiting for ")) {
    return createFailureInfo("request_timeout", message, { method: options.method });
  }

  if (lowered.includes("failed to start lsp server")) {
    return createFailureInfo("spawn_failed", message, { method: options.method });
  }

  if (lowered.includes("outside workspace")) {
    return createFailureInfo("outside_workspace", message, { method: options.method });
  }

  if (lowered.includes("abort") || lowered.includes("cancel")) {
    return createFailureInfo("aborted", message, { method: options.method });
  }

  if (options.method === "initialize") {
    return createFailureInfo("initialize_failed", message, { method: options.method });
  }

  if (lowered.includes("exited")) {
    return createFailureInfo("process_exited", message, { method: options.method });
  }

  return createFailureInfo("initialize_failed", message, { method: options.method });
}

export class LspServer {
  private process: ChildProcessWithoutNullStreams | undefined;
  private parser = new JsonRpcStreamParser();
  private requestId = 1;
  private startedAt: number | undefined;
  private initializedAt: number | undefined;
  private readyAt: number | undefined;
  private failedAt: number | undefined;
  private restartCount = 0;
  private state: ServerLifecycleState = "stopped";
  private lastProcessError: Error | undefined;
  private lastFailure: LspFailureInfo | undefined;
  private lastRequest: RequestMetric | undefined;
  private startPromise: Promise<void> | undefined;
  private intentionalStop = false;
  private stderrBuffer = "";
  private readonly pendingRequests = new Map<number, PendingRequest>();
  private readonly unsupportedMethods = new Set<string>();
  private readonly documents = new Map<string, OpenDocument>();
  private readonly diagnostics = new Map<string, DiagnosticEntry>();
  private readonly diagnosticWaiters = new Map<string, DiagnosticsWaiter[]>();
  private readonly activeProgressTokens = new Set<string>();
  private kotlinProgressObserved = false;
  private kotlinLastProgressAt: number | undefined;
  private kotlinReadyFallbackTimer: ReturnType<typeof setTimeout> | undefined;
  private readonly recentStderrLines: string[] = [];
  private readonly recentLogLines: string[] = [];
  private readonly language: SupportedLanguage;
  private readonly root: string;
  private readonly config: ServerConfig;
  private readonly spawnProcess: typeof spawn;
  private readonly findCompetingWorkspacePids: typeof findCompetingKotlinWorkspacePids;
  private readonly onStatusChange: (() => void) | undefined;

  constructor(
    language: SupportedLanguage,
    root: string,
    config: ServerConfig,
    spawnProcess: typeof spawn = spawn,
    findCompetingWorkspacePids: typeof findCompetingKotlinWorkspacePids = findCompetingKotlinWorkspacePids,
    onStatusChange?: () => void,
  ) {
    this.language = language;
    this.root = root;
    this.config = config;
    this.spawnProcess = spawnProcess;
    this.findCompetingWorkspacePids = findCompetingWorkspacePids;
    this.onStatusChange = onStatusChange;
  }

  async start(): Promise<void> {
    if (this.state === "ready") return;
    if (this.startPromise) return this.startPromise;

    this.startPromise = this.startInternal();
    try {
      await this.startPromise;
    } finally {
      this.startPromise = undefined;
    }
  }

  async restart(): Promise<void> {
    this.restartCount += 1;
    this.transitionState("restarting");
    await this.stop();
    await this.start();
  }

  async waitUntilReady(options: { signal?: AbortSignal; maxWaitMs?: number; acceptIndexing?: boolean } = {}): Promise<void> {
    const { signal, maxWaitMs = DEFAULT_REQUEST_TIMEOUT_MS, acceptIndexing = false } = options;

    if (this.state === "ready" || (acceptIndexing && this.state === "indexing")) return;
    if (this.state === "failed") throw this.lastProcessError ?? new Error(`LSP server failed for ${this.language}`);

    const deadline = Date.now() + maxWaitMs;

    while (true) {
      if (signal?.aborted) {
        throw new Error(`Aborted while waiting for LSP server readiness for ${this.language}`);
      }
      if (this.state === "ready" || (acceptIndexing && this.state === "indexing")) return;
      if (this.state === "failed") throw this.lastProcessError ?? new Error(`LSP server failed for ${this.language}`);
      if (Date.now() >= deadline) {
        throw new LspReadinessTimeoutError(this.language, this.root, this.state, maxWaitMs);
      }
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }

  async stop(): Promise<void> {
    if (!this.process) {
      this.transitionState("stopped");
      this.clearProcessBoundState();
      return;
    }

    try {
      await this.request("shutdown", null, 5_000);
    } catch {
      // Ignore shutdown failures.
    }

    try {
      await this.notify("exit", null);
    } catch {
      // Ignore exit failures.
    }

    this.intentionalStop = true;
    this.terminateProcess();
    this.transitionState("stopped");
    this.clearProcessBoundState();
  }

  async request(method: string, params: unknown, timeoutMs = DEFAULT_REQUEST_TIMEOUT_MS): Promise<any> {
    const requestStartedAt = Date.now();

    try {
      if (this.unsupportedMethods.has(method)) {
        throw new UnsupportedLspMethodError(method, this.language, this.root, getServerLabel(this.config.command));
      }

      if (!this.process?.stdin.writable) {
        throw this.lastProcessError ?? new Error(`LSP server is not running for ${this.language}`);
      }

      const id = this.requestId++;
      const payload = {
        jsonrpc: "2.0",
        id,
        method,
        params,
      };

      const responsePromise = new Promise<any>((resolve, reject) => {
        const timer = setTimeout(() => {
          this.pendingRequests.delete(id);
          reject(new Error(`Timed out waiting for ${method} from ${this.language}`));
        }, timeoutMs);

        this.pendingRequests.set(id, {
          method,
          reject: (error) => {
            clearTimeout(timer);
            reject(error);
          },
          resolve: (value) => {
            clearTimeout(timer);
            resolve(value);
          },
        });
      });

      this.writeMessage(payload);
      const result = await responsePromise;
      if (this.shouldMarkReadyAfterRequest(method)) {
        this.markSemanticReady();
      }
      this.recordRequestMetric(method, requestStartedAt, true);
      return result;
    } catch (error) {
      const normalized = toError(error);
      this.recordRequestMetric(method, requestStartedAt, false, normalized);
      this.lastFailure = classifyLspFailure(normalized, {
        method,
        language: this.language,
        root: this.root,
        currentPid: this.process?.pid,
      });
      throw normalized;
    }
  }

  async notify(method: string, params: unknown): Promise<void> {
    this.writeMessage({
      jsonrpc: "2.0",
      method,
      params,
    });
  }

  async syncDocument(filePath: string): Promise<{ uri: string; version: number; changed: boolean }> {
    const absolutePath = fs.realpathSync.native(filePath);
    const uri = pathToFileURL(absolutePath).href;
    const text = fs.readFileSync(absolutePath, "utf8");
    const current = this.documents.get(uri);

    if (!current) {
      this.documents.set(uri, { text, version: 1 });
      await this.notify("textDocument/didOpen", {
        textDocument: {
          uri,
          languageId: LANGUAGE_IDS[this.language],
          version: 1,
          text,
        },
      });
      return { uri, version: 1, changed: true };
    }

    if (current.text === text) {
      return { uri, version: current.version, changed: false };
    }

    const nextVersion = current.version + 1;
    this.documents.set(uri, { text, version: nextVersion });
    await this.notify("textDocument/didChange", {
      textDocument: {
        uri,
        version: nextVersion,
      },
      contentChanges: [{ text }],
    });
    return { uri, version: nextVersion, changed: true };
  }

  async getDiagnostics(filePath: string): Promise<Diagnostic[]> {
    const requestedAt = Date.now();
    const { uri, version, changed } = await this.syncDocument(filePath);
    const current = this.diagnostics.get(uri);

    if (current && (!changed || this.isDiagnosticsFresh(current, version, requestedAt))) {
      if (this.language === "kotlin" && this.isDiagnosticsFresh(current, version, requestedAt)) {
        this.markSemanticReady();
      }
      return current.diagnostics;
    }

    const diagnostics = await this.waitForDiagnostics(
      uri,
      version,
      requestedAt,
      DEFAULT_DIAGNOSTICS_TIMEOUT_MS,
      current?.diagnostics ?? [],
    );
    const latest = this.diagnostics.get(uri);
    if (this.language === "kotlin" && latest && this.isDiagnosticsFresh(latest, version, requestedAt)) {
      this.markSemanticReady();
    }
    return diagnostics;
  }

  getStatus(): ServerStatus {
    return {
      language: this.language,
      root: this.root,
      pid: this.process?.pid,
      state: this.state,
      startedAt: this.startedAt,
      initializedAt: this.initializedAt,
      readyAt: this.readyAt,
      failedAt: this.failedAt,
      openDocuments: this.documents.size,
      restartCount: this.restartCount,
      lastFailure: this.lastFailure,
      lastStderrLines: [...this.recentStderrLines],
      lastRequest: this.lastRequest,
    };
  }

  getRecentLogLines(): string[] {
    return [...this.recentLogLines];
  }

  private async startInternal(): Promise<void> {
    if (this.process && this.state !== "failed" && this.state !== "stopped") return;

    this.intentionalStop = false;
    this.parser = new JsonRpcStreamParser();
    this.stderrBuffer = "";
    this.unsupportedMethods.clear();
    this.lastProcessError = undefined;
    this.lastFailure = undefined;
    this.failedAt = undefined;
    this.initializedAt = undefined;
    this.readyAt = undefined;
    this.startedAt = Date.now();
    this.transitionState("starting");

    if (this.language === "kotlin") {
      const competingWorkspacePids = this.findCompetingWorkspacePids(this.root);
      if (competingWorkspacePids.length > 0) {
        const error = new KotlinWorkspaceSessionConflictError(
          "initialize",
          this.language,
          this.root,
          getServerLabel(this.config.command),
          competingWorkspacePids,
        );
        this.recordFailure(
          classifyLspFailure(error, {
            method: "initialize",
            language: this.language,
            root: this.root,
          }),
          error,
        );
        throw error;
      }
    }

    const child = this.spawnProcess(this.config.command, this.config.args ?? [], {
      cwd: this.root,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.process = child;
    this.addLogLine(`[lifecycle] spawned ${getServerLabel(this.config.command)} pid ${child.pid ?? "unknown"}`);
    this.transitionState("initializing");

    child.stdout.on("data", (chunk: Buffer) => {
      for (const message of this.parser.push(chunk)) {
        this.handleMessage(message);
      }
    });

    child.stderr.on("data", (chunk: Buffer | string) => {
      this.captureStderr(chunk.toString());
    });

    child.on("error", (error) => {
      this.handleProcessFailure(
        error instanceof Error
          ? new Error(`Failed to start LSP server for ${this.language} (${this.root}): ${error.message}`)
          : new Error(`Failed to start LSP server for ${this.language} (${this.root}).`),
      );
    });

    child.on("exit", (code, signal) => {
      this.flushPendingStderr();
      this.handleProcessFailure(
        this.lastProcessError
          ?? new Error(`LSP server exited for ${this.language} (${this.root})${formatExitSuffix(code, signal)}`),
      );
    });

    const timeoutMs = this.config.startupTimeoutMs ?? 20_000;
    try {
      await this.request(
        "initialize",
        {
          processId: process.pid,
          clientInfo: {
            name: "pi-lsp",
            version: "0.1.0",
          },
          rootUri: pathToFileURL(this.root).href,
          capabilities: {
            textDocument: {
              definition: {},
              documentSymbol: {
                hierarchicalDocumentSymbolSupport: true,
              },
              hover: {
                contentFormat: ["markdown", "plaintext"],
              },
              publishDiagnostics: {},
              references: {},
            },
            window: {
              workDoneProgress: true,
            },
            workspace: {
              symbol: {},
              workspaceFolders: true,
            },
          },
          workspaceFolders: [
            {
              uri: pathToFileURL(this.root).href,
              name: path.basename(this.root),
            },
          ],
        },
        timeoutMs,
      );
      this.initializedAt = Date.now();
      if (this.language === "kotlin") {
        // Kotlin may emit progress notifications immediately after `initialized`, so
        // enter `indexing` first to avoid missing the promotion to `ready`.
        this.enterKotlinIndexing();
      }
      await this.notify("initialized", {});
      if (this.language !== "kotlin") {
        this.readyAt = Date.now();
        this.transitionState("ready");
      }
    } catch (error) {
      const normalized = toError(error);
      this.lastProcessError = normalized;
      this.recordFailure(
        classifyLspFailure(normalized, {
          method: "initialize",
          language: this.language,
          root: this.root,
          currentPid: this.process?.pid,
        }),
        normalized,
      );
      this.terminateProcess();
      throw normalized;
    }
  }

  private handleMessage(message: any): void {
    if (typeof message?.method === "string") {
      if (message.method === "textDocument/publishDiagnostics") {
        const params = message.params as { uri?: string; version?: number; diagnostics?: Diagnostic[] } | undefined;
        if (params?.uri) {
          const entry: DiagnosticEntry = {
            diagnostics: params.diagnostics ?? [],
            updatedAt: Date.now(),
            version: typeof params.version === "number" ? params.version : undefined,
          };
          this.diagnostics.set(params.uri, entry);
          this.settleDiagnosticWaiters(params.uri, entry);
        }
        return;
      }

      if (message.method === "$/progress") {
        this.handleProgressNotification(message.params);
        return;
      }

      if (isJsonRpcRequestId(message.id)) {
        this.handleServerRequest(message.id, message.method, message.params);
      }
      return;
    }

    if (typeof message?.id === "number") {
      const pending = this.pendingRequests.get(message.id);
      if (!pending) return;
      this.pendingRequests.delete(message.id);

      if (message.error) {
        if (isMethodNotSupportedResponse(pending.method, message.error)) {
          this.unsupportedMethods.add(pending.method);
          pending.reject(
            new UnsupportedLspMethodError(
              pending.method,
              this.language,
              this.root,
              getServerLabel(this.config.command),
            ),
          );
        } else if (isNoProjectResponse(pending.method, message.error)) {
          pending.reject(
            new LspNoProjectError(
              pending.method,
              this.language,
              this.root,
              getServerLabel(this.config.command),
            ),
          );
        } else {
          pending.reject(new Error(message.error.message ?? `LSP request failed: ${message.id}`));
        }
      } else {
        pending.resolve(message.result);
      }
    }
  }

  private handleServerRequest(id: number | string, method: string, params: unknown): void {
    switch (method) {
      case "window/workDoneProgress/create": {
        const token = normalizeProgressToken((params as { token?: unknown } | undefined)?.token);
        this.addLogLine(`[server-request] ${method}${token ? ` ${token}` : ""} ok`);
        this.writeMessage({
          jsonrpc: "2.0",
          id,
          result: null,
        });
        return;
      }
      default:
        this.addLogLine(`[server-request] unsupported ${method}`);
        this.writeMessage({
          jsonrpc: "2.0",
          id,
          error: {
            code: -32601,
            message: `Unsupported server request: ${method}`,
          },
        });
    }
  }

  private handleProgressNotification(params: unknown): void {
    const payload = params as { token?: unknown; value?: WorkDoneProgressValue } | undefined;
    const token = normalizeProgressToken(payload?.token);
    const value = payload?.value;
    if (!token || !value || typeof value !== "object") return;

    const summary = summarizeProgress(value);
    if (this.language === "kotlin") {
      this.kotlinProgressObserved = true;
      this.kotlinLastProgressAt = Date.now();
    }

    if (value.kind === "begin") {
      this.activeProgressTokens.add(token);
      this.addLogLine(`[progress] begin${summary ? ` ${summary}` : ""}`);
      this.scheduleKotlinStalledProgressFallback();
      return;
    }

    if (value.kind === "report") {
      if (summary) this.addLogLine(`[progress] report ${summary}`);
      this.scheduleKotlinStalledProgressFallback();
      return;
    }

    if (value.kind === "end") {
      this.activeProgressTokens.delete(token);
      this.addLogLine(`[progress] end${summary ? ` ${summary}` : ""}`);
      if (this.language === "kotlin" && this.state === "indexing" && this.activeProgressTokens.size === 0) {
        this.markSemanticReady();
        return;
      }
      this.scheduleKotlinStalledProgressFallback();
    }
  }

  private writeMessage(message: unknown): void {
    if (!this.process?.stdin.writable) {
      throw this.lastProcessError ?? new Error(`LSP server stdin is unavailable for ${this.language}`);
    }
    const body = JSON.stringify(message);
    this.process.stdin.write(`Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`);
  }

  private terminateProcess(): void {
    if (!this.process) return;
    this.process.kill();
    this.process = undefined;
  }

  private handleProcessFailure(error: Error): void {
    const normalized = toError(error);

    if (this.intentionalStop) {
      this.intentionalStop = false;
      this.lastProcessError = normalized;
      this.rejectPendingRequests(normalized);
      this.rejectDiagnosticWaiters(normalized);
      this.process = undefined;
      return;
    }

    if (!this.lastProcessError) this.lastProcessError = normalized;
    this.rejectPendingRequests(this.lastProcessError);
    this.rejectDiagnosticWaiters(this.lastProcessError);
    const failedPid = this.process?.pid;
    this.process = undefined;
    this.recordFailure(
      classifyLspFailure(this.lastProcessError, {
        method: this.state === "starting" || this.state === "initializing" ? "initialize" : undefined,
        language: this.language,
        root: this.root,
        currentPid: failedPid,
      }),
      this.lastProcessError,
    );
    this.clearProcessBoundState();
  }

  private shouldMarkReadyAfterRequest(method: string): boolean {
    if (this.language !== "kotlin") return false;
    return [
      "workspace/symbol",
      "textDocument/hover",
      "textDocument/definition",
      "textDocument/references",
      "textDocument/documentSymbol",
    ].includes(method);
  }

  private enterKotlinIndexing(): void {
    this.clearKotlinProgressState();
    this.transitionState("indexing");
    this.scheduleKotlinReadyWithoutProgressFallback();
  }

  private scheduleKotlinReadyWithoutProgressFallback(): void {
    if (this.language !== "kotlin") return;

    this.clearKotlinReadyFallbackTimer();
    const delayMs = this.config.kotlinReadyWithoutProgressMs ?? DEFAULT_KOTLIN_READY_WITHOUT_PROGRESS_MS;
    this.kotlinReadyFallbackTimer = setTimeout(() => {
      if (this.state !== "indexing") return;
      if (this.kotlinProgressObserved) return;
      if (this.activeProgressTokens.size > 0) return;

      this.addLogLine(`[progress] no Kotlin work-done progress observed after ${delayMs}ms; assuming ready`);
      this.markSemanticReady();
    }, delayMs);
  }

  private scheduleKotlinStalledProgressFallback(): void {
    if (this.language !== "kotlin") return;
    if (this.state !== "indexing") return;
    if (!this.kotlinProgressObserved) return;

    this.clearKotlinReadyFallbackTimer();
    const delayMs = this.config.kotlinStalledProgressTimeoutMs ?? DEFAULT_KOTLIN_STALLED_PROGRESS_TIMEOUT_MS;
    this.kotlinReadyFallbackTimer = setTimeout(() => {
      if (this.state !== "indexing") return;
      if (!this.kotlinProgressObserved) return;
      if (!this.kotlinLastProgressAt) return;
      if (Date.now() - this.kotlinLastProgressAt < delayMs) return;

      const activeTokenCount = this.activeProgressTokens.size;
      const activeTokenSuffix = activeTokenCount > 0 ? ` with ${activeTokenCount} active progress token(s)` : "";
      this.addLogLine(`[progress] Kotlin progress stalled for ${delayMs}ms${activeTokenSuffix}; assuming ready`);
      this.markSemanticReady();
    }, delayMs);
  }

  private clearKotlinReadyFallbackTimer(): void {
    if (!this.kotlinReadyFallbackTimer) return;
    clearTimeout(this.kotlinReadyFallbackTimer);
    this.kotlinReadyFallbackTimer = undefined;
  }

  private clearKotlinProgressState(): void {
    this.clearKotlinReadyFallbackTimer();
    this.kotlinProgressObserved = false;
    this.kotlinLastProgressAt = undefined;
  }

  private markSemanticReady(): void {
    this.clearKotlinReadyFallbackTimer();
    if (this.state === "ready") return;
    this.readyAt = Date.now();
    this.transitionState("ready");
  }

  private transitionState(nextState: ServerLifecycleState): void {
    if (this.state === nextState) return;
    const previous = this.state;
    this.state = nextState;
    this.addLogLine(`[lifecycle] ${previous} -> ${nextState}`);
    this.onStatusChange?.();
  }

  private recordFailure(failure: LspFailureInfo, error: Error): void {
    this.lastFailure = failure;
    this.lastProcessError = error;
    this.failedAt = failure.at;
    this.transitionState("failed");
    this.addLogLine(`[failure] ${failure.category}: ${failure.message}`);
  }

  private recordRequestMetric(method: string, startedAt: number, ok: boolean, error?: Error): void {
    const completedAt = Date.now();
    this.lastRequest = {
      method,
      startedAt,
      completedAt,
      durationMs: completedAt - startedAt,
      ok,
      error: error?.message,
    };

    const outcome = ok ? "ok" : `error: ${error?.message ?? "unknown"}`;
    this.addLogLine(`[request] ${method} ${outcome} (${this.lastRequest.durationMs}ms)`);
  }

  private addLogLine(message: string): void {
    pushBounded(this.recentLogLines, `${timestampPrefix(Date.now())} ${message}`, MAX_RECENT_LOG_LINES);
  }

  private captureStderr(text: string): void {
    this.stderrBuffer += text;
    const normalized = this.stderrBuffer.replace(/\r\n/g, "\n");
    const parts = normalized.split("\n");
    this.stderrBuffer = parts.pop() ?? "";

    for (const line of parts) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      pushBounded(this.recentStderrLines, trimmed, MAX_RECENT_STDERR_LINES);
      this.addLogLine(`[stderr] ${trimmed}`);
    }
  }

  private flushPendingStderr(): void {
    const trimmed = this.stderrBuffer.trim();
    if (!trimmed) return;
    pushBounded(this.recentStderrLines, trimmed, MAX_RECENT_STDERR_LINES);
    this.addLogLine(`[stderr] ${trimmed}`);
    this.stderrBuffer = "";
  }

  private clearProcessBoundState(): void {
    this.documents.clear();
    this.diagnostics.clear();
    this.unsupportedMethods.clear();
    this.activeProgressTokens.clear();
    this.clearKotlinProgressState();
    this.initializedAt = undefined;
    this.readyAt = undefined;
    if (this.state !== "failed") this.startedAt = undefined;
  }

  private rejectPendingRequests(error: Error): void {
    for (const pending of this.pendingRequests.values()) pending.reject(error);
    this.pendingRequests.clear();
  }

  private rejectDiagnosticWaiters(error: Error): void {
    for (const waiters of this.diagnosticWaiters.values()) {
      for (const waiter of waiters) {
        clearTimeout(waiter.timer);
        waiter.reject(error);
      }
    }
    this.diagnosticWaiters.clear();
  }

  private isDiagnosticsFresh(entry: DiagnosticEntry, targetVersion: number, requestedAt: number): boolean {
    if (typeof entry.version === "number") return entry.version >= targetVersion;
    return entry.updatedAt >= requestedAt;
  }

  private waitForDiagnostics(
    uri: string,
    targetVersion: number,
    requestedAt: number,
    timeoutMs: number,
    fallbackDiagnostics: Diagnostic[],
  ): Promise<Diagnostic[]> {
    const current = this.diagnostics.get(uri);
    if (current && this.isDiagnosticsFresh(current, targetVersion, requestedAt)) {
      return Promise.resolve(current.diagnostics);
    }

    return new Promise<Diagnostic[]>((resolve, reject) => {
      const waiter: DiagnosticsWaiter = {
        requestedAt,
        targetVersion,
        reject,
        resolve,
        timer: setTimeout(() => {
          this.removeDiagnosticWaiter(uri, waiter);
          resolve(this.diagnostics.get(uri)?.diagnostics ?? fallbackDiagnostics);
        }, timeoutMs),
      };

      const waiters = this.diagnosticWaiters.get(uri) ?? [];
      waiters.push(waiter);
      this.diagnosticWaiters.set(uri, waiters);
    });
  }

  private removeDiagnosticWaiter(uri: string, waiter: DiagnosticsWaiter): void {
    const waiters = this.diagnosticWaiters.get(uri);
    if (!waiters) return;

    const remaining = waiters.filter((candidate) => candidate !== waiter);
    if (remaining.length > 0) this.diagnosticWaiters.set(uri, remaining);
    else this.diagnosticWaiters.delete(uri);
  }

  private settleDiagnosticWaiters(uri: string, entry: DiagnosticEntry): void {
    const waiters = this.diagnosticWaiters.get(uri);
    if (!waiters || waiters.length === 0) return;

    const remaining: DiagnosticsWaiter[] = [];
    for (const waiter of waiters) {
      if (this.isDiagnosticsFresh(entry, waiter.targetVersion, waiter.requestedAt)) {
        clearTimeout(waiter.timer);
        waiter.resolve(entry.diagnostics);
      } else {
        remaining.push(waiter);
      }
    }

    if (remaining.length > 0) this.diagnosticWaiters.set(uri, remaining);
    else this.diagnosticWaiters.delete(uri);
  }
}

export class ServerManager {
  private readonly servers = new Map<string, LspServer>();
  private readonly starting = new Map<string, Promise<LspServer>>();
  private readonly config: ExtensionConfig;
  private readonly statusListeners = new Set<() => void>();

  constructor(config: ExtensionConfig) {
    this.config = config;
  }

  onStatusChange(listener: () => void): () => void {
    this.statusListeners.add(listener);
    return () => {
      this.statusListeners.delete(listener);
    };
  }

  getOrCreate(language: SupportedLanguage, root: string): LspServer {
    return this.ensureServer(language, root);
  }

  startInBackground(language: SupportedLanguage, root: string): LspServer {
    const key = this.getKey(language, root);
    const server = this.ensureServer(language, root);
    const state = server.getStatus().state;

    if (state === "ready" || state === "starting" || state === "initializing" || state === "indexing") {
      return server;
    }

    if (!this.starting.has(key)) {
      const startPromise = (async () => {
        await server.start();
        return server;
      })();

      this.starting.set(key, startPromise);
      void startPromise.catch(() => undefined).finally(() => {
        this.starting.delete(key);
      });
    }

    return server;
  }

  warm(language: SupportedLanguage, root: string): LspServer {
    return this.startInBackground(language, root);
  }

  async restart(language?: SupportedLanguage, root?: string): Promise<void> {
    const servers = this.selectServers(language, root);
    await Promise.all(servers.map((server) => server.restart()));
  }

  async stop(language?: SupportedLanguage, root?: string): Promise<void> {
    const entries = this.selectServerEntries(language, root);
    await Promise.all(entries.map(([, server]) => server.stop()));

    for (const [key] of entries) {
      this.starting.delete(key);
      this.servers.delete(key);
    }

    this.notifyStatusChange();
  }

  getConfiguredLanguages(): SupportedLanguage[] {
    return Object.entries(this.config.servers)
      .filter(([, serverConfig]) => serverConfig)
      .map(([language]) => language as SupportedLanguage);
  }

  getStatus(): ServerStatus[] {
    return Array.from(this.servers.values(), (server) => server.getStatus()).sort((left, right) => {
      if (left.language === right.language) return left.root.localeCompare(right.root);
      return left.language.localeCompare(right.language);
    });
  }

  getRecentLogLines(language?: SupportedLanguage, root?: string): string[] {
    return this.selectServers(language, root).flatMap((server) => server.getRecentLogLines());
  }

  async shutdown(): Promise<void> {
    await Promise.all(Array.from(this.servers.values(), (server) => server.stop()));
    this.servers.clear();
    this.starting.clear();
    this.notifyStatusChange();
  }

  private ensureServer(language: SupportedLanguage, root: string): LspServer {
    const key = this.getKey(language, root);
    const existing = this.servers.get(key);
    if (existing) return existing;

    const serverConfig = this.config.servers[language];
    if (!serverConfig) {
      throw new Error(`No LSP server configured for ${language}.`);
    }

    const server = new LspServer(language, root, serverConfig, spawn, findCompetingKotlinWorkspacePids, () => {
      this.notifyStatusChange();
    });
    this.servers.set(key, server);
    return server;
  }

  private selectServerEntries(language?: SupportedLanguage, root?: string): Array<[string, LspServer]> {
    return Array.from(this.servers.entries()).filter(([, server]) => {
      const status = server.getStatus();
      if (language && status.language !== language) return false;
      if (root && status.root !== root) return false;
      return true;
    });
  }

  private selectServers(language?: SupportedLanguage, root?: string): LspServer[] {
    return this.selectServerEntries(language, root).map(([, server]) => server);
  }

  private getKey(language: SupportedLanguage, root: string): string {
    return `${language}:${root}`;
  }

  private notifyStatusChange(): void {
    for (const listener of this.statusListeners) listener();
  }
}
