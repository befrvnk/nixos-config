import type { BashToolDetails, TruncationResult } from "@earendil-works/pi-coding-agent";
import type { BashOutputView } from "./filtering.ts";

export function shouldPersistFullOutput(view: BashOutputView): boolean {
  return view.stats.omittedMatchingLines > 0
    || view.stats.truncatedByBytes
    || (view.stats.hasFilters && view.stats.matchedLines < view.stats.totalLines);
}

export function buildBashToolDetails(
  view: BashOutputView,
  fullOutputPath?: string,
): BashToolDetails {
  const truncated = shouldPersistFullOutput(view);
  const truncation: TruncationResult = {
    content: view.text,
    truncated,
    truncatedBy: view.stats.truncatedByBytes ? "bytes" : truncated ? "lines" : null,
    totalLines: view.stats.totalLines,
    totalBytes: view.stats.outputBytes,
    outputLines: view.stats.displayedLines,
    outputBytes: view.stats.displayedBytes,
  };

  return {
    truncation,
    fullOutputPath,
  };
}
