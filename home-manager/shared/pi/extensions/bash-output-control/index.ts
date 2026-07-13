import { StringDecoder } from "node:string_decoder";
import { spawn, type ChildProcess } from "node:child_process";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  BashOutputViewAccumulator,
  DEFAULT_BASH_MAX_BYTES,
  DEFAULT_BASH_TAIL_LINES,
  formatByteSize,
  MAX_BASH_MAX_BYTES,
  MAX_BASH_TAIL_LINES,
  normalizeBashOutputViewOptions,
  summarizeFilters,
  type BashOutputView,
  type BashOutputViewOptions,
} from "./filtering.ts";
import { buildBashToolDetails, shouldPersistFullOutput } from "./details.ts";
import { LazyOutputLog } from "./output-log.ts";

const TIMEOUT_KILL_GRACE_MS = 2_000;

const FilterMode = StringEnum(["regex", "literal"] as const, {
  description:
    'How include/exclude filters are interpreted. "regex" uses JavaScript regular expressions; "literal" treats patterns as plain text.',
  default: "regex",
});

const bashSchema = Type.Object({
  command: Type.String({ description: "Bash command to execute" }),
  timeout: Type.Optional(Type.Number({ description: "Timeout in seconds (optional, no default timeout)" })),
  tailLines: Type.Optional(
    Type.Number({
      description: `How many lines from the bottom of the filtered output to print. Default: ${DEFAULT_BASH_TAIL_LINES}. Set to 0 to hide command output and only report status. If output is truncated or filtered, the full output is saved to the system temp directory. Max: ${MAX_BASH_TAIL_LINES}.`,
    }),
  ),
  maxBytes: Type.Optional(
    Type.Number({
      description: `Maximum bytes to print after tailing/filtering. Default: ${formatByteSize(DEFAULT_BASH_MAX_BYTES)}. Max: ${formatByteSize(MAX_BASH_MAX_BYTES)}. If output is truncated or filtered, the full output is saved to the system temp directory.`,
    }),
  ),
  include: Type.Optional(
    Type.Array(
      Type.String({
        description:
          "Only print lines matching at least one of these patterns. Interpreted as regex by default; set filterMode='literal' for plain text.",
      }),
    ),
  ),
  exclude: Type.Optional(
    Type.Array(
      Type.String({
        description:
          "Drop lines matching any of these patterns. Interpreted as regex by default; set filterMode='literal' for plain text.",
      }),
    ),
  ),
  filterMode: Type.Optional(FilterMode),
  ignoreCase: Type.Optional(Type.Boolean({ description: "Match include/exclude filters case-insensitively" })),
});

type BashParams = {
  command: string;
  timeout?: number;
} & BashOutputViewOptions;

function signalProcessGroup(child: ChildProcess, signal: NodeJS.Signals): void {
  if (!child.pid) return;

  try {
    if (process.platform !== "win32") process.kill(-child.pid, signal);
    else child.kill(signal);
  } catch {
    try {
      child.kill(signal);
    } catch {
      // Process already exited.
    }
  }
}

type LocalBashResult = {
  exitCode: number | null;
};

type LocalBashOptions = {
  cwd: string;
  command: string;
  timeout?: number;
  signal?: AbortSignal;
  onStdout: (text: string) => Promise<void>;
  onStderr: (text: string) => Promise<void>;
};

async function consumeReadable(
  stream: NodeJS.ReadableStream | null,
  decoder: StringDecoder,
  onText: (text: string) => Promise<void>,
): Promise<void> {
  if (!stream) return;
  for await (const chunk of stream) {
    const text = decoder.write(chunk as Buffer);
    if (text) await onText(text);
  }
  const finalText = decoder.end();
  if (finalText) await onText(finalText);
}

function waitForChild(child: ChildProcess): Promise<number | null> {
  return new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("close", (code) => resolve(code));
  });
}

async function execLocalBash(options: LocalBashOptions): Promise<LocalBashResult> {
  if (options.signal?.aborted) throw new Error("aborted");

  const child = spawn("bash", ["-lc", options.command], {
    cwd: options.cwd,
    detached: process.platform !== "win32",
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });

  const stdoutDecoder = new StringDecoder("utf8");
  const stderrDecoder = new StringDecoder("utf8");
  let timedOut = false;
  let timeoutHandle: NodeJS.Timeout | undefined;
  let killHandle: NodeJS.Timeout | undefined;

  const onAbort = () => {
    signalProcessGroup(child, "SIGTERM");
    killHandle ??= setTimeout(() => signalProcessGroup(child, "SIGKILL"), TIMEOUT_KILL_GRACE_MS);
  };

  const stdoutTask = consumeReadable(child.stdout, stdoutDecoder, options.onStdout);
  const stderrTask = consumeReadable(child.stderr, stderrDecoder, options.onStderr);

  try {
    if (options.timeout !== undefined && options.timeout > 0) {
      timeoutHandle = setTimeout(() => {
        timedOut = true;
        signalProcessGroup(child, "SIGTERM");
        killHandle ??= setTimeout(() => signalProcessGroup(child, "SIGKILL"), TIMEOUT_KILL_GRACE_MS);
      }, options.timeout * 1000);
    }

    if (options.signal) options.signal.addEventListener("abort", onAbort, { once: true });

    const [exitCode] = await Promise.all([waitForChild(child), stdoutTask, stderrTask]);
    if (options.signal?.aborted) throw new Error("aborted");
    if (timedOut) throw new Error(`timeout:${options.timeout}`);
    return { exitCode };
  } catch (error) {
    signalProcessGroup(child, "SIGKILL");
    throw error;
  } finally {
    if (timeoutHandle) clearTimeout(timeoutHandle);
    if (killHandle) clearTimeout(killHandle);
    if (options.signal) options.signal.removeEventListener("abort", onAbort);
  }
}

function buildFooter(view: BashOutputView, options: BashOutputViewOptions, fullOutputPath?: string): string {
  const normalized = normalizeBashOutputViewOptions(options);
  const parts: string[] = [];

  if (view.stats.hasFilters) {
    parts.push(`Displayed ${view.stats.displayedLines} of ${view.stats.matchedLines} matching lines`);
  } else {
    parts.push(`Displayed ${view.stats.displayedLines} of ${view.stats.totalLines} lines`);
  }

  if (view.stats.omittedMatchingLines > 0) {
    parts.push(`${view.stats.omittedMatchingLines} earlier matching lines omitted by tailLines=${normalized.tailLines}`);
  }

  if (view.stats.truncatedByBytes) {
    parts.push(`Trimmed to last ${formatByteSize(view.stats.displayedBytes)} by maxBytes=${formatByteSize(normalized.maxBytes)}`);
  }

  const filters = summarizeFilters(options);
  if (filters) parts.push(`Filters: ${filters}`);

  parts.push(`Full output size: ${formatByteSize(view.stats.outputBytes)}`);
  if (fullOutputPath) parts.push(`Full output: ${fullOutputPath}`);

  return `[${parts.join(". ")}]`;
}

function outputBody(view: BashOutputView, params: BashParams, fullOutputPath?: string, status?: string): string {
  let text = view.text;
  if (!text) {
    if (view.stats.outputBytes === 0) {
      text = "(no output)";
    } else if (view.stats.hasFilters && view.stats.matchedLines === 0) {
      text = "(no lines matched filters)";
    } else {
      text = "(output hidden by tailLines/maxBytes settings)";
    }
  }

  if (status) text += `\n\n${status}`;
  text += `\n\n${buildFooter(view, params, fullOutputPath)}`;
  return text;
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "bash",
    label: "bash",
    description:
      `Execute a bash command in the current working directory. Printed output can be reduced with include/exclude filters, tailLines (default ${DEFAULT_BASH_TAIL_LINES}), and maxBytes (default ${formatByteSize(DEFAULT_BASH_MAX_BYTES)}). ` +
      "When the displayed output is incomplete because lines were filtered or truncated, the full output is saved to the system temp directory and the path is included at the end of the result.",
    promptSnippet: "Execute bash commands with configurable output filtering/tailing; full output is saved to the system temp directory when displayed output is incomplete",
    promptGuidelines: [
      "Use bash tailLines, include, exclude, filterMode, ignoreCase, and maxBytes to keep noisy command output small; when displayed output is incomplete, a full output path is reported at the end.",
      "For noisy build tools such as Gradle, Maven, npm, or test runners, prefer bash include/exclude filters and a small tailLines value before rerunning commands.",
      "Use read on the bash-reported temp output file, when present, only if the displayed output is insufficient.",
    ],
    parameters: bashSchema,

    async execute(_toolCallId, params: BashParams, signal, _onUpdate, ctx) {
      // Normalize options and construct the accumulator before starting the command;
      // accumulator construction compiles regex filters so invalid patterns fail fast.
      const normalized = normalizeBashOutputViewOptions(params);
      const accumulator = new BashOutputViewAccumulator(params);
      const outputLog = new LazyOutputLog(normalized.maxBytes);

      let view: BashOutputView | undefined;
      const finishOutput = async () => {
        view ??= accumulator.finish();
        if (shouldPersistFullOutput(view)) await outputLog.enable();
        const fullOutputPath = await outputLog.finish();
        return { view, fullOutputPath };
      };

      try {
        let exitCode: number | null;
        try {
          const appendOutput = async (text: string) => {
            accumulator.append(text);
            await outputLog.append(text);
          };

          const result = await execLocalBash({
            command: params.command,
            cwd: ctx.cwd,
            signal,
            timeout: params.timeout,
            onStdout: appendOutput,
            onStderr: appendOutput,
          });
          exitCode = result.exitCode;
        } catch (error) {
          const { view: errorView, fullOutputPath } = await finishOutput();
          if (error instanceof Error && error.message === "aborted") {
            throw new Error(outputBody(errorView, params, fullOutputPath, "Command aborted"));
          }
          if (error instanceof Error && error.message.startsWith("timeout:")) {
            const timeoutSecs = error.message.split(":")[1];
            throw new Error(outputBody(errorView, params, fullOutputPath, `Command timed out after ${timeoutSecs} seconds`));
          }
          const message = error instanceof Error ? error.message : String(error);
          throw new Error(outputBody(errorView, params, fullOutputPath, `Command failed: ${message}`));
        }

        const { view: finalView, fullOutputPath } = await finishOutput();
        if (exitCode !== 0 && exitCode !== null) {
          throw new Error(outputBody(finalView, params, fullOutputPath, `Command exited with code ${exitCode}`));
        }

        return {
          content: [{ type: "text", text: outputBody(finalView, params, fullOutputPath) }],
          details: buildBashToolDetails(finalView, fullOutputPath),
        };
      } finally {
        try {
          if (!view) await finishOutput();
          else await outputLog.finish();
        } catch {
          // The command result/error is more useful than a temp-file close error.
        }
      }
    },
  });
}
