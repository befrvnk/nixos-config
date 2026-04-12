import { Clipboard, getSelectedText } from "@vicinae/api";
import type { SourcePreference } from "./types.js";

async function safeSelectedText(): Promise<string> {
  try {
    return await getSelectedText();
  } catch {
    return "";
  }
}

async function safeClipboardText(): Promise<string> {
  try {
    return (await Clipboard.readText()) ?? "";
  } catch {
    return "";
  }
}

function hasText(value: string): boolean {
  return value.trim().length > 0;
}

export async function readSourceText(preferredSource: SourcePreference): Promise<string> {
  const selected = await safeSelectedText();
  const clipboard = await safeClipboardText();

  if (preferredSource === "clipboard") {
    if (hasText(clipboard)) return clipboard;
    if (hasText(selected)) return selected;
  } else {
    if (hasText(selected)) return selected;
    if (hasText(clipboard)) return clipboard;
  }

  throw new Error("No text found in the preferred source or its fallback.");
}

export function markdownCodeBlock(text: string): string {
  return ["```text", text || "(empty)", "```"].join("\n");
}
