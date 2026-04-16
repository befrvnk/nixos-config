import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { LANGUAGE_IDS } from "./constants.js";
import type {
  Diagnostic,
  ExtensionConfig,
  OpenDocument,
  ServerConfig,
  ServerStatus,
  SupportedLanguage,
} from "./types.js";

const DEFAULT_DIAGNOSTICS_TIMEOUT_MS = 5_000;

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

export function isMethodNotSupportedResponse(method: string, error: unknown): boolean {
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

export class LspServer {
  private process: ChildProcessWithoutNullStreams | undefined;
  private parser = new JsonRpcStreamParser();
  private requestId = 1;
  private started = false;
  private startedAt: number | undefined;
  private lastProcessError: Error | undefined;
  private readonly pendingRequests = new Map<number, PendingRequest>();
  private readonly unsupportedMethods = new Set<string>();
  private readonly documents = new Map<string, OpenDocument>();
  private readonly diagnostics = new Map<string, DiagnosticEntry>();
  private readonly diagnosticWaiters = new Map<string, DiagnosticsWaiter[]>();
  private readonly language: SupportedLanguage;
  private readonly root: string;
  private readonly config: ServerConfig;
  private readonly spawnProcess: typeof spawn;

  constructor(
    language: SupportedLanguage,
    root: string,
    config: ServerConfig,
    spawnProcess: typeof spawn = spawn,
  ) {
    this.language = language;
    this.root = root;
    this.config = config;
    this.spawnProcess = spawnProcess;
  }

  async start(): Promise<void> {
    if (this.started) return;

    this.unsupportedMethods.clear();

    const child = this.spawnProcess(this.config.command, this.config.args ?? [], {
      cwd: this.root,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.process = child;
    this.lastProcessError = undefined;

    child.stdout.on("data", (chunk: Buffer) => {
      for (const message of this.parser.push(chunk)) {
        this.handleMessage(message);
      }
    });

    child.stderr.on("data", () => {
      // Intentionally ignored for now. The tool should stay passive and on-demand.
    });

    child.on("error", (error) => {
      this.handleProcessFailure(
        error instanceof Error
          ? new Error(`Failed to start LSP server for ${this.language} (${this.root}): ${error.message}`)
          : new Error(`Failed to start LSP server for ${this.language} (${this.root}).`),
      );
    });

    child.on("exit", (code, signal) => {
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
      await this.notify("initialized", {});
      this.started = true;
      this.startedAt = Date.now();
    } catch (error) {
      if (error instanceof Error) this.lastProcessError = error;
      this.terminateProcess();
      throw error;
    }
  }

  async stop(): Promise<void> {
    if (!this.process) return;

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

    this.terminateProcess();
    this.started = false;
    this.startedAt = undefined;
    this.unsupportedMethods.clear();
  }

  async request(method: string, params: unknown, timeoutMs = 15_000): Promise<any> {
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
    return responsePromise;
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
      return current.diagnostics;
    }

    return this.waitForDiagnostics(uri, version, requestedAt, DEFAULT_DIAGNOSTICS_TIMEOUT_MS, current?.diagnostics ?? []);
  }

  private handleMessage(message: any): void {
    if (message?.method === "textDocument/publishDiagnostics") {
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

  getStatus(): ServerStatus {
    return {
      language: this.language,
      root: this.root,
      pid: this.process?.pid,
      startedAt: this.startedAt,
      openDocuments: this.documents.size,
    };
  }

  private handleProcessFailure(error: Error): void {
    if (!this.lastProcessError) this.lastProcessError = error;
    this.rejectPendingRequests(this.lastProcessError);
    this.rejectDiagnosticWaiters(this.lastProcessError);
    this.started = false;
    this.startedAt = undefined;
    this.process = undefined;
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

  constructor(config: ExtensionConfig) {
    this.config = config;
  }

  async get(language: SupportedLanguage, root: string): Promise<LspServer> {
    const key = `${language}:${root}`;
    const existing = this.servers.get(key);
    if (existing) return existing;

    const inFlight = this.starting.get(key);
    if (inFlight) return inFlight;

    const serverConfig = this.config.servers[language];
    if (!serverConfig) {
      throw new Error(`No LSP server configured for ${language}.`);
    }

    const startPromise = (async () => {
      const server = new LspServer(language, root, serverConfig);
      await server.start();
      this.servers.set(key, server);
      return server;
    })();

    this.starting.set(key, startPromise);
    try {
      return await startPromise;
    } finally {
      this.starting.delete(key);
    }
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

  async shutdown(): Promise<void> {
    await Promise.all(Array.from(this.servers.values(), (server) => server.stop()));
    this.servers.clear();
    this.starting.clear();
  }
}
