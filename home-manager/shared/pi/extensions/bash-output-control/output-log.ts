import { randomUUID } from "node:crypto";
import { once } from "node:events";
import { createWriteStream, type WriteStream } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

function tempOutputPath(): string {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  return join(tmpdir(), `pi-bash-${stamp}-${randomUUID().slice(0, 8)}.log`);
}

function finishStream(stream: WriteStream): Promise<void> {
  if (stream.destroyed || stream.closed) return Promise.resolve();

  return new Promise((resolve, reject) => {
    stream.once("error", reject);
    stream.end(() => resolve());
  });
}

export class LazyOutputLog {
  private stream: WriteStream | undefined;
  private chunks: string[] = [];
  private bufferedBytes = 0;
  private finishPromise: Promise<string | undefined> | undefined;
  private streamError: Error | undefined;
  private pendingWrite = Promise.resolve();
  path: string | undefined;

  constructor(private readonly maxBufferedBytes: number) {}

  async append(text: string): Promise<void> {
    if (this.finishPromise) return;

    if (!this.stream) {
      this.chunks.push(text);
      this.bufferedBytes += Buffer.byteLength(text, "utf8");
      if (this.bufferedBytes > this.maxBufferedBytes) await this.enable();
      return;
    }

    await this.enqueueWrite(text);
  }

  async enable(): Promise<void> {
    if (this.stream || this.finishPromise) return;

    this.path = tempOutputPath();
    this.stream = createWriteStream(this.path, {
      encoding: "utf8",
      flags: "wx",
      mode: 0o600,
    });
    this.stream.on("error", (error) => {
      this.streamError = error;
    });

    const buffered = this.chunks;
    this.chunks = [];
    this.bufferedBytes = 0;
    for (const chunk of buffered) await this.enqueueWrite(chunk);
  }

  async finish(): Promise<string | undefined> {
    this.finishPromise ??= this.finishOnce();
    return this.finishPromise;
  }

  private async finishOnce(): Promise<string | undefined> {
    this.chunks = [];
    this.bufferedBytes = 0;
    if (!this.stream) return undefined;

    await this.pendingWrite;
    if (this.streamError) throw this.streamError;
    await finishStream(this.stream);
    if (this.streamError) throw this.streamError;
    return this.path;
  }

  private enqueueWrite(text: string): Promise<void> {
    this.pendingWrite = this.pendingWrite.then(async () => {
      if (!this.stream || this.stream.destroyed) throw new Error("Bash output log is unavailable.");
      if (this.streamError) throw this.streamError;
      if (!this.stream.write(text)) await once(this.stream, "drain");
      if (this.streamError) throw this.streamError;
    });
    return this.pendingWrite;
  }
}
