import { getPreferenceValues } from "@vicinae/api";

export type Preferences = {
  gap?: string;
  paddingTop?: string;
  paddingBottom?: string;
  paddingLeft?: string;
  paddingRight?: string;
  activationDelayMs?: string;
  almostMaximizePercent?: string;
};

export type WindowPreferences = {
  gap: number;
  paddingTop: number;
  paddingBottom: number;
  paddingLeft: number;
  paddingRight: number;
  activationDelayMs: number;
  almostMaximizePercent: number;
};

function parseNumber(value: string | undefined, fallback: number, options: { min?: number; max?: number } = {}): number {
  if (value === undefined || value.trim() === "") return fallback;

  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;

  const min = options.min ?? Number.NEGATIVE_INFINITY;
  const max = options.max ?? Number.POSITIVE_INFINITY;
  return Math.min(max, Math.max(min, parsed));
}

export function getWindowPreferences(): WindowPreferences {
  const preferences = getPreferenceValues<Preferences>();

  return {
    gap: parseNumber(preferences.gap, 0, { min: 0 }),
    paddingTop: parseNumber(preferences.paddingTop, 0, { min: 0 }),
    paddingBottom: parseNumber(preferences.paddingBottom, 0, { min: 0 }),
    paddingLeft: parseNumber(preferences.paddingLeft, 0, { min: 0 }),
    paddingRight: parseNumber(preferences.paddingRight, 0, { min: 0 }),
    activationDelayMs: parseNumber(preferences.activationDelayMs, 120, { min: 0, max: 1000 }),
    almostMaximizePercent: parseNumber(preferences.almostMaximizePercent, 90, { min: 10, max: 100 }),
  };
}
