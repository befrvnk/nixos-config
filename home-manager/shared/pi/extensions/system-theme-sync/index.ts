import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

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

export function parseLinuxTheme(output: string): ThemeMode | undefined {
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

export function applyTheme(ctx: ExtensionContext, mode: ThemeMode): ThemeMode {
  const result = ctx.ui.setTheme(THEMES[mode]);
  if (!result.success) {
    throw new Error(result.error ?? `Failed to set ${mode} theme.`);
  }
  return mode;
}

export async function syncThemeSafely(
  ctx: ExtensionContext,
  options: {
    currentTheme?: ThemeMode;
    detect?: () => Promise<ThemeMode | undefined>;
    notifyError?: (message: string) => void;
    shouldApply?: () => boolean;
  } = {},
): Promise<ThemeMode | undefined> {
  const currentTheme = options.currentTheme;
  try {
    const detectedTheme = await (options.detect ?? detectTheme)();
    if (options.shouldApply && !options.shouldApply()) return currentTheme;
    if (!detectedTheme || detectedTheme === currentTheme) return currentTheme;
    return applyTheme(ctx, detectedTheme);
  } catch (error) {
    if (options.shouldApply && !options.shouldApply()) return currentTheme;
    options.notifyError?.(
      error instanceof Error ? error.message : String(error),
    );
    return currentTheme;
  }
}

export function createSerializedPoller(
  task: () => Promise<void>,
  intervalMs: number,
  timers: {
    schedule?: (callback: () => void, delay: number) => unknown;
    cancel?: (handle: unknown) => void;
  } = {},
) {
  const schedule = timers.schedule ?? ((callback, delay) => setTimeout(callback, delay));
  const cancel = timers.cancel ?? ((handle) => clearTimeout(handle as ReturnType<typeof setTimeout>));
  let active = false;
  let timeout: unknown;

  const run = async () => {
    try {
      await task();
    } finally {
      if (active) timeout = schedule(() => void run(), intervalMs);
    }
  };

  return {
    async start() {
      if (active) return;
      active = true;
      await run();
    },
    stop() {
      active = false;
      if (timeout !== undefined) cancel(timeout);
      timeout = undefined;
    },
  };
}

export default function systemThemeSyncExtension(pi: ExtensionAPI) {
  let poller: ReturnType<typeof createSerializedPoller> | undefined;
  let activeOwner: symbol | undefined;
  let currentTheme: ThemeMode | undefined;
  let lastSyncError: string | undefined;

  const stop = () => {
    activeOwner = undefined;
    poller?.stop();
    poller = undefined;
  };

  const reportSyncError = (ctx: ExtensionContext, message: string) => {
    if (!ctx.hasUI || !message || message === lastSyncError) return;
    lastSyncError = message;
    ctx.ui.notify(`Theme sync failed: ${message}`, "warning");
  };

  pi.on("session_start", async (_event, ctx) => {
    stop();
    currentTheme = undefined;
    lastSyncError = undefined;

    if (ctx.mode !== "tui") return;

    const owner = Symbol("system-theme-sync-session");
    activeOwner = owner;
    poller = createSerializedPoller(async () => {
      if (activeOwner !== owner) return;
      const nextTheme = await syncThemeSafely(ctx, {
        currentTheme,
        shouldApply: () => activeOwner === owner,
        notifyError: (message) => reportSyncError(ctx, message),
      });
      if (activeOwner !== owner) return;
      currentTheme = nextTheme;
      if (currentTheme) lastSyncError = undefined;
    }, POLL_INTERVAL_MS);
    await poller.start();
  });

  pi.on("session_shutdown", () => {
    stop();
    currentTheme = undefined;
    lastSyncError = undefined;
  });
}
