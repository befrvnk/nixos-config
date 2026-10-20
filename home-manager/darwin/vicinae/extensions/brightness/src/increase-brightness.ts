import { adjustBrightness, runBrightnessAction } from "./lib/better-display.js";
import { getPreferences } from "./lib/preferences.js";

export default async function IncreaseBrightness(): Promise<void> {
  const { step } = getPreferences();
  await runBrightnessAction("Increase Brightness", () => adjustBrightness(step));
}
