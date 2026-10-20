import {
  Clipboard,
  Toast,
  closeMainWindow,
  sendDesktopNotification,
  showToast,
} from "@vicinae/api";
import { rewriteWithGemini } from "./gemini.js";
import { getPreferences } from "./preferences.js";
import { readSourceText } from "./text.js";
import type { QuickAction, RewritePreset, SourcePreference } from "./types.js";

export async function handleOutput(action: QuickAction, text: string): Promise<void> {
  if (action === "paste") {
    await Clipboard.paste(text);
    await closeMainWindow();
    return;
  }

  await Clipboard.copy(text);
}

export async function runQuickPreset(
  preset: RewritePreset,
  source?: SourcePreference,
  action?: QuickAction,
): Promise<void> {
  const preferences = getPreferences();
  const outputAction = action ?? preferences.action;
  const loadingToast = await showToast({
    style: Toast.Style.Animated,
    title: `${preset.title}…`,
    message: "Sending request to Gemini",
  });

  try {
    const sourceText = await readSourceText(source ?? preferences.source);
    const rewritten = await rewriteWithGemini({
      apiKey: preferences.apiKey,
      model: preferences.model,
      instruction: preset.instruction,
      sourceText,
      customInstructions: preferences.customInstructions,
    });

    await handleOutput(outputAction, rewritten);

    loadingToast.style = Toast.Style.Success;
    loadingToast.title = preset.successTitle;
    loadingToast.message =
      outputAction === "paste"
        ? "Pasted into the active application"
        : "Copied to the clipboard";
    await loadingToast.update();
    await sendDesktopNotification({
      title: preset.successTitle,
      body: outputAction === "paste" ? "Pasted into the active application" : "Copied to the clipboard",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    loadingToast.style = Toast.Style.Failure;
    loadingToast.title = `${preset.title} failed`;
    loadingToast.message = message;
    await loadingToast.update();
    await sendDesktopNotification({
      title: `${preset.title} failed`,
      body: message,
    });
  }
}
