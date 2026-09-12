import { getPreferenceValues } from "@vicinae/api";
import type { Preferences, QuickAction, SourcePreference } from "./types.js";

export function getPreferences(): Required<Preferences> {
  const prefs = getPreferenceValues<Preferences>();
  const model = prefs.model?.startsWith("gemini-2.5-") ? "gemini-3.8-flash" : prefs.model;

  return {
    apiKey: prefs.apiKey ?? "",
    model: model ?? "gemini-3.8-flash",
    source: (prefs.source ?? "selected") as SourcePreference,
    action: (prefs.action ?? "paste") as QuickAction,
    customInstructions: prefs.customInstructions ?? "",
  };
}
