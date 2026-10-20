import { adjustBrightness, runBrightnessAction } from "./lib/better-display.js";
import { getPreferences } from "./lib/preferences.js";

export default async function DecreaseBrightness(): Promise<void> {
  const { step } = getPreferences();
  await runBrightnessAction("Decrease Brightness", () => adjustBrightness(-step));
}
