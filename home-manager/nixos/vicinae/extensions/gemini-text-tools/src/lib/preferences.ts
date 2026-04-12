import { getPreferenceValues } from "@vicinae/api";
import type { Preferences, QuickAction, SourcePreference } from "./types.js";

export function getPreferences(): Required<Preferences> {
  const prefs = getPreferenceValues<Preferences>();

  return {
    apiKey: prefs.apiKey ?? "",
    model: prefs.model ?? "gemini-2.5-flash",
    source: (prefs.source ?? "selected") as SourcePreference,
    action: (prefs.action ?? "paste") as QuickAction,
    customInstructions: prefs.customInstructions ?? "",
  };
}
