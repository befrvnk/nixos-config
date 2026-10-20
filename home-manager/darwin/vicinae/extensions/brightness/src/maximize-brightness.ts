import { runBrightnessAction, setBrightnessPercent } from "./lib/better-display.js";

export default async function MaximizeBrightness(): Promise<void> {
  await runBrightnessAction("Maximize Brightness", () => setBrightnessPercent(100));
}
