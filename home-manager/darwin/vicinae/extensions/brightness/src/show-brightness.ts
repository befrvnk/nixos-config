import { getBrightnessPercent, runBrightnessAction } from "./lib/better-display.js";

export default async function ShowBrightness(): Promise<void> {
  await runBrightnessAction("Current Brightness", () => getBrightnessPercent());
}
