import { chmod, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  DEFAULT_MAX_BYTES,
  DEFAULT_MAX_LINES,
  formatSize,
  truncateHead,
  type TruncationResult,
} from "@earendil-works/pi-coding-agent";

export interface PreparedToolOutput {
  text: string;
  fullOutputPath?: string;
  truncation?: TruncationResult;
}

export async function prepareToolOutput(
  displayText: string,
  options: {
    fullText?: string;
    prefix: string;
    signal?: AbortSignal;
  },
): Promise<PreparedToolOutput> {
  const fullText = options.fullText ?? displayText;
  const initial = truncateHead(displayText, {
    maxBytes: DEFAULT_MAX_BYTES,
    maxLines: DEFAULT_MAX_LINES,
  });
  if (!initial.truncated && fullText === displayText) return { text: displayText };

  options.signal?.throwIfAborted();
  const directory = await mkdtemp(join(tmpdir(), "pi-search-tools-"));
  await chmod(directory, 0o700);
  const fullOutputPath = join(directory, `${options.prefix}.md`);
  await writeFile(fullOutputPath, fullText, { encoding: "utf8", mode: 0o600 });
  options.signal?.throwIfAborted();

  const totalLines = fullText.length === 0 ? 0 : fullText.split("\n").length;
  const footer = `[Output truncated. Full output (${totalLines} lines, ${formatSize(Buffer.byteLength(fullText, "utf8"))}) saved to: ${fullOutputPath}]`;
  const footerBytes = Buffer.byteLength(`\n\n${footer}`, "utf8");
  const footerLines = 2;
  const truncation = truncateHead(displayText, {
    maxBytes: Math.max(1, DEFAULT_MAX_BYTES - footerBytes),
    maxLines: Math.max(1, DEFAULT_MAX_LINES - footerLines),
  });

  return {
    text: `${truncation.content}\n\n${footer}`,
    fullOutputPath,
    truncation,
  };
}
