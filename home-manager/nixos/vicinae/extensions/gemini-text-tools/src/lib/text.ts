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

function assertSafeSourceText(value: string): string {
  const text = value.trim();
  if (/^AIza[A-Za-z0-9_-]{35}$/.test(text)) {
    throw new Error("The input resembles a Google API key and will not be sent. Select the text you want to rewrite.");
  }
  return value;
}

export async function readSourceText(preferredSource: SourcePreference): Promise<string> {
  if (preferredSource === "clipboard") {
    const clipboard = await safeClipboardText();
    if (hasText(clipboard)) return assertSafeSourceText(clipboard);
    throw new Error("No clipboard text found. Copy the text you want to rewrite and try again.");
  }

  const selected = await safeSelectedText();
  if (hasText(selected)) return assertSafeSourceText(selected);
  throw new Error("No selected text found. Select text before opening Vicinae and try again.");
}

export function markdownCodeBlock(text: string): string {
  return ["```text", text || "(empty)", "```"].join("\n");
}
