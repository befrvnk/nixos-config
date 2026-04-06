import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { getCacheRoot } from "./config.js";
import { LANGUAGE_IDS } from "./constants.js";
import type { Diagnostic, ExtensionConfig, OpenDocument, ServerConfig, SupportedLanguage } from "./types.js";

class JsonRpcStreamParser {
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

export class LspServer {
  private process: ChildProcessWithoutNullStreams | undefined;
  private parser = new JsonRpcStreamParser();
  private requestId = 1;
  private started = false;
  private readonly pendingRequests = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void }>();
  private readonly documents = new Map<string, OpenDocument>();
  private readonly diagnostics = new Map<string, Diagnostic[]>();
  private readonly language: SupportedLanguage;
  private readonly root: string;
  private readonly config: ServerConfig;

  constructor(language: SupportedLanguage, root: string, config: ServerConfig) {
    this.language = language;
    this.root = root;
    this.config = config;
  }

  async start(): Promise<void> {
    if (this.started) return;

    const args = [...(this.config.args ?? [])];
    if (this.language === "java") {
      args.push("-data", this.getJavaWorkspaceDir());
    }

    this.process = spawn(this.config.command, args, {
      cwd: this.root,
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });

    this.process.stdout.on("data", (chunk: Buffer) => {
      for (const message of this.parser.push(chunk)) {
        this.handleMessage(message);
      }
    });

    this.process.stderr.on("data", () => {
      // Intentionally ignored for now. The tool should stay passive and on-demand.
    });

    this.process.on("exit", () => {
      const error = new Error(`LSP server exited for ${this.language} (${this.root})`);
      for (const pending of this.pendingRequests.values()) pending.reject(error);
      this.pendingRequests.clear();
      this.started = false;
      this.process = undefined;
    });

    const timeoutMs = this.config.startupTimeoutMs ?? 20_000;
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

    this.process.kill();
    this.process = undefined;
    this.started = false;
  }

  async request(method: string, params: unknown, timeoutMs = 15_000): Promise<any> {
    if (!this.process?.stdin.writable) throw new Error(`LSP server is not running for ${this.language}`);

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

  async syncDocument(filePath: string): Promise<void> {
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
      return;
    }

    if (current.text === text) return;

    const nextVersion = current.version + 1;
    this.documents.set(uri, { text, version: nextVersion });
    await this.notify("textDocument/didChange", {
      textDocument: {
        uri,
        version: nextVersion,
      },
      contentChanges: [{ text }],
    });
  }

  async getDiagnostics(filePath: string): Promise<Diagnostic[]> {
    await this.syncDocument(filePath);
    await new Promise((resolve) => setTimeout(resolve, 300));
    return this.diagnostics.get(pathToFileURL(fs.realpathSync.native(filePath)).href) ?? [];
  }

  private handleMessage(message: any): void {
    if (message?.method === "textDocument/publishDiagnostics") {
      const params = message.params as { uri?: string; diagnostics?: Diagnostic[] } | undefined;
      if (params?.uri) {
        this.diagnostics.set(params.uri, params.diagnostics ?? []);
      }
      return;
    }

    if (typeof message?.id === "number") {
      const pending = this.pendingRequests.get(message.id);
      if (!pending) return;
      this.pendingRequests.delete(message.id);

      if (message.error) {
        pending.reject(new Error(message.error.message ?? `LSP request failed: ${message.id}`));
      } else {
        pending.resolve(message.result);
      }
    }
  }

  private writeMessage(message: unknown): void {
    if (!this.process?.stdin.writable) throw new Error(`LSP server stdin is unavailable for ${this.language}`);
    const body = JSON.stringify(message);
    this.process.stdin.write(`Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`);
  }

  private getJavaWorkspaceDir(): string {
    const cacheRoot = getCacheRoot();
    const hash = createHash("sha1").update(this.root).digest("hex");
    const dir = path.join(cacheRoot, "jdtls", hash);
    fs.mkdirSync(dir, { recursive: true });
    return dir;
  }
}

export class ServerManager {
  private readonly servers = new Map<string, LspServer>();
  private readonly config: ExtensionConfig;

  constructor(config: ExtensionConfig) {
    this.config = config;
  }

  async get(language: SupportedLanguage, root: string): Promise<LspServer> {
    const key = `${language}:${root}`;
    const existing = this.servers.get(key);
    if (existing) return existing;

    const serverConfig = this.config.servers[language];
    if (!serverConfig) {
      throw new Error(`No LSP server configured for ${language}.`);
    }

    const server = new LspServer(language, root, serverConfig);
    await server.start();
    this.servers.set(key, server);
    return server;
  }

  async shutdown(): Promise<void> {
    await Promise.all(Array.from(this.servers.values(), (server) => server.stop()));
    this.servers.clear();
  }
}
