import { getPreferenceValues } from "@vicinae/api";

export type DisplayTarget = "displayWithMouse" | "displayWithMainStatus" | "displayWithFocus";

type Preferences = {
  step?: string;
  display?: string;
  cliPath?: string;
};

export type BrightnessPreferences = {
  step: number;
  display: DisplayTarget;
  cliPath: string;
};

const defaultCliPath = "/opt/homebrew/bin/betterdisplaycli";

const displayTargets: DisplayTarget[] = [
  "displayWithMouse",
  "displayWithMainStatus",
  "displayWithFocus",
];

function parseStep(value: string | undefined): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 10;
  return Math.min(100, Math.max(1, Math.round(parsed)));
}

function parseDisplay(value: string | undefined): DisplayTarget {
  return displayTargets.includes(value as DisplayTarget)
    ? (value as DisplayTarget)
    : "displayWithMouse";
}

export function getPreferences(): BrightnessPreferences {
  const preferences = getPreferenceValues<Preferences>();

  return {
    step: parseStep(preferences.step),
    display: parseDisplay(preferences.display),
    cliPath: preferences.cliPath?.trim() || defaultCliPath,
  };
}
