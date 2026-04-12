import {
  Clipboard,
  Toast,
  closeMainWindow,
  showToast,
} from "@vicinae/api";
import { rewriteWithGemini } from "./gemini.js";
import { getPreferences } from "./preferences.js";
import { readSourceText } from "./text.js";
import type { QuickAction, RewritePreset } from "./types.js";

export async function handleOutput(action: QuickAction, text: string): Promise<void> {
  if (action === "paste") {
    await Clipboard.paste(text);
    await closeMainWindow();
    return;
  }

  await Clipboard.copy(text);
}

export async function runQuickPreset(preset: RewritePreset): Promise<void> {
  const preferences = getPreferences();
  const loadingToast = await showToast({
    style: Toast.Style.Animated,
    title: `${preset.title}…`,
    message: "Sending request to Gemini",
  });

  try {
    const sourceText = await readSourceText(preferences.source);
    const rewritten = await rewriteWithGemini({
      apiKey: preferences.apiKey,
      model: preferences.model,
      instruction: preset.instruction,
      sourceText,
      customInstructions: preferences.customInstructions,
    });

    await handleOutput(preferences.action, rewritten);

    loadingToast.style = Toast.Style.Success;
    loadingToast.title = preset.successTitle;
    loadingToast.message =
      preferences.action === "paste"
        ? "Pasted into the active application"
        : "Copied to the clipboard";
    await loadingToast.update();
  } catch (error) {
    loadingToast.style = Toast.Style.Failure;
    loadingToast.title = `${preset.title} failed`;
    loadingToast.message = error instanceof Error ? error.message : String(error);
    await loadingToast.update();
  }
}
