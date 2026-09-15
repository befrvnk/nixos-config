import { Toast, sendDesktopNotification, showToast } from "@vicinae/api";
import { execFile } from "node:child_process";
import { getPreferences } from "./preferences.js";

function runCli(args: string[]): Promise<string> {
  const { cliPath } = getPreferences();

  return new Promise<string>((resolve, reject) => {
    execFile(cliPath, args, (error, stdout, stderr) => {
      if (!error) {
        resolve(stdout.trim());
        return;
      }

      reject(new Error(stderr.trim() || error.message));
    });
  });
}

export async function getBrightnessPercent(): Promise<number> {
  const { display } = getPreferences();
  const output = await runCli(["get", `-${display}`, "-brightness"]);
  const value = Number.parseFloat(output);

  if (!Number.isFinite(value)) {
    throw new Error(`Unexpected BetterDisplay output: ${output}`);
  }

  return Math.round(value * 100);
}

export async function setBrightnessPercent(level: number): Promise<number> {
  const { display } = getPreferences();
  const clamped = Math.max(0, Math.min(100, Math.round(level)));

  await runCli(["set", `-${display}`, `-brightness=${clamped}%`]);
  return clamped;
}

export async function adjustBrightness(amount: number): Promise<number> {
  const { display } = getPreferences();
  const magnitude = Math.max(1, Math.round(Math.abs(amount)));
  const sign = amount >= 0 ? "" : "-";

  await runCli(["set", `-${display}`, `-brightness=${sign}${magnitude}%`, "-offset"]);
  return getBrightnessPercent();
}

export async function runBrightnessAction(
  title: string,
  action: () => Promise<number>,
): Promise<void> {
  try {
    const level = await action();
    await sendDesktopNotification({ title, body: `Brightness: ${level}%` });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Vicinae brightness action failed (${title})`, error);
    await showToast({ style: Toast.Style.Failure, title: `${title} failed`, message });
    await sendDesktopNotification({ title: `${title} failed`, body: message });
  }
}
