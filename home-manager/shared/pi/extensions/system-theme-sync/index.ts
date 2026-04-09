import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

const execFileAsync = promisify(execFile);
const POLL_INTERVAL_MS = 2000;
const THEMES = {
  dark: "dark",
  light: "light",
} as const;

type ThemeMode = keyof typeof THEMES;

async function run(command: string, args: string[]): Promise<string> {
  const { stdout } = await execFileAsync(command, args, {
    timeout: 1500,
    windowsHide: true,
  });
  return stdout.trim();
}

async function getMacTheme(): Promise<ThemeMode | undefined> {
  try {
    const output = await run("osascript", [
      "-e",
      'tell application "System Events" to tell appearance preferences to return dark mode',
    ]);
    if (output === "true") return "dark";
    if (output === "false") return "light";
  } catch {
    return undefined;
  }

  return undefined;
}

function parseLinuxTheme(output: string): ThemeMode | undefined {
  const normalized = output.trim().toLowerCase();
  if (!normalized) return undefined;
  if (normalized.includes("dark")) return "dark";
  if (normalized.includes("light") || normalized.includes("default")) return "light";
  return undefined;
}

async function getLinuxTheme(): Promise<ThemeMode | undefined> {
  try {
    const output = await run("dconf", ["read", "/org/gnome/desktop/interface/color-scheme"]);
    const theme = parseLinuxTheme(output);
    if (theme) return theme;
  } catch {
    // Fall through to other detectors.
  }

  try {
    const output = await run("darkman", ["get"]);
    const theme = parseLinuxTheme(output);
    if (theme) return theme;
  } catch {
    return undefined;
  }

  return undefined;
}

async function detectTheme(): Promise<ThemeMode | undefined> {
  switch (process.platform) {
    case "darwin":
      return getMacTheme();
    case "linux":
      return getLinuxTheme();
    default:
      return undefined;
  }
}

function applyTheme(ctx: ExtensionContext, mode: ThemeMode): ThemeMode {
  const result = ctx.ui.setTheme(THEMES[mode]);
  if (!result.success) {
    throw new Error(result.error ?? `Failed to set ${mode} theme.`);
  }
  return mode;
}

export default function systemThemeSyncExtension(pi: ExtensionAPI) {
  let intervalId: ReturnType<typeof setInterval> | undefined;
  let currentTheme: ThemeMode | undefined;

  const stop = () => {
    if (!intervalId) return;
    clearInterval(intervalId);
    intervalId = undefined;
  };

  const syncTheme = async (ctx: ExtensionContext) => {
    const detectedTheme = await detectTheme();
    if (!detectedTheme || detectedTheme === currentTheme) return;
    currentTheme = applyTheme(ctx, detectedTheme);
  };

  pi.on("session_start", async (_event, ctx) => {
    stop();
    currentTheme = undefined;

    if (!ctx.hasUI) return;

    await syncTheme(ctx);

    intervalId = setInterval(() => {
      void syncTheme(ctx);
    }, POLL_INTERVAL_MS);
  });

  pi.on("session_shutdown", () => {
    stop();
    currentTheme = undefined;
  });
}
