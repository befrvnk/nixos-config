import {
  Clipboard,
  closeMainWindow,
  LocalStorage,
  Toast,
  WindowManagement,
  sendDesktopNotification,
  showToast,
} from "@vicinae/api";
import { hasInternalSetWindowBounds, setWindowBounds, type Bounds } from "./internal-window-management";
import { getWindowPreferences } from "./preferences";

export type Rect = {
  x: number;
  y: number;
  width: number;
  height: number;
};

type Screen = WindowManagement.Screen;
type Window = WindowManagement.Window;

type ScreenContext = {
  window: Window;
  screen: Screen;
  screens: Screen[];
  workArea: Rect;
};

export type LayoutKind =
  | "left-half"
  | "right-half"
  | "top-half"
  | "bottom-half"
  | "maximize"
  | "almost-maximize"
  | "center"
  | "top-left"
  | "top-right"
  | "bottom-left"
  | "bottom-right"
  | "first-third"
  | "center-third"
  | "last-third"
  | "two-thirds-left"
  | "two-thirds-right";

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function boundsToRect(bounds: Bounds): Rect {
  return {
    x: bounds.position.x,
    y: bounds.position.y,
    width: bounds.size.width,
    height: bounds.size.height,
  };
}

function rectToBounds(rect: Rect): Bounds {
  return {
    position: { x: rect.x, y: rect.y },
    size: { width: rect.width, height: rect.height },
  };
}

function screenToRect(screen: Screen): Rect {
  return {
    x: screen.bounds.position.x,
    y: screen.bounds.position.y,
    width: screen.bounds.size.width,
    height: screen.bounds.size.height,
  };
}

function insetRect(rect: Rect, insets: { top: number; bottom: number; left: number; right: number }): Rect {
  return {
    x: rect.x + insets.left,
    y: rect.y + insets.top,
    width: Math.max(1, rect.width - insets.left - insets.right),
    height: Math.max(1, rect.height - insets.top - insets.bottom),
  };
}

function addGap(rect: Rect, gap: number): Rect {
  return insetRect(rect, { top: gap, bottom: gap, left: gap, right: gap });
}

function centerOf(rect: Rect): { x: number; y: number } {
  return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
}

function containsPoint(rect: Rect, point: { x: number; y: number }): boolean {
  return point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height;
}

function distanceSquared(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return (a.x - b.x) ** 2 + (a.y - b.y) ** 2;
}

function findScreenForWindow(window: Window, screens: Screen[]): Screen {
  const windowCenter = centerOf(boundsToRect(window.bounds));
  const containing = screens.find((screen) => containsPoint(screenToRect(screen), windowCenter));
  if (containing) return containing;

  return screens.reduce((nearest, screen) => {
    const nearestDistance = distanceSquared(centerOf(screenToRect(nearest)), windowCenter);
    const screenDistance = distanceSquared(centerOf(screenToRect(screen)), windowCenter);
    return screenDistance < nearestDistance ? screen : nearest;
  });
}

function clampRectToArea(rect: Rect, area: Rect): Rect {
  const width = Math.min(rect.width, area.width);
  const height = Math.min(rect.height, area.height);
  return {
    width,
    height,
    x: Math.min(Math.max(rect.x, area.x), area.x + area.width - width),
    y: Math.min(Math.max(rect.y, area.y), area.y + area.height - height),
  };
}

function centeredRect(area: Rect, width: number, height: number): Rect {
  return {
    x: area.x + (area.width - width) / 2,
    y: area.y + (area.height - height) / 2,
    width,
    height,
  };
}

function storageKey(window: Window): string {
  return `previous-bounds:${window.id}`;
}

async function savePreviousBounds(window: Window): Promise<void> {
  await LocalStorage.setItem(storageKey(window), JSON.stringify(boundsToRect(window.bounds)));
}

async function getActiveWindowContext(): Promise<ScreenContext> {
  const preferences = getWindowPreferences();

  await closeMainWindow({ clearRootSearch: true });
  await sleep(preferences.activationDelayMs);

  const [window, screens] = await Promise.all([WindowManagement.getActiveWindow(), WindowManagement.getScreens()]);
  if (screens.length === 0) {
    throw new Error("No display information available");
  }

  const screen = findScreenForWindow(window, screens);
  const workArea = insetRect(screenToRect(screen), {
    top: preferences.paddingTop,
    bottom: preferences.paddingBottom,
    left: preferences.paddingLeft,
    right: preferences.paddingRight,
  });

  return { window, screens, screen, workArea };
}

export function computeLayout(kind: LayoutKind, ctx: ScreenContext): Rect {
  const preferences = getWindowPreferences();
  const area = ctx.workArea;
  const gap = preferences.gap;

  switch (kind) {
    case "left-half":
      return addGap({ x: area.x, y: area.y, width: area.width / 2, height: area.height }, gap);
    case "right-half":
      return addGap({ x: area.x + area.width / 2, y: area.y, width: area.width / 2, height: area.height }, gap);
    case "top-half":
      return addGap({ x: area.x, y: area.y, width: area.width, height: area.height / 2 }, gap);
    case "bottom-half":
      return addGap({ x: area.x, y: area.y + area.height / 2, width: area.width, height: area.height / 2 }, gap);
    case "maximize":
      return addGap(area, gap);
    case "almost-maximize": {
      const ratio = preferences.almostMaximizePercent / 100;
      return centeredRect(area, area.width * ratio, area.height * ratio);
    }
    case "center": {
      const current = boundsToRect(ctx.window.bounds);
      return clampRectToArea(centeredRect(area, current.width, current.height), area);
    }
    case "top-left":
      return addGap({ x: area.x, y: area.y, width: area.width / 2, height: area.height / 2 }, gap);
    case "top-right":
      return addGap({ x: area.x + area.width / 2, y: area.y, width: area.width / 2, height: area.height / 2 }, gap);
    case "bottom-left":
      return addGap({ x: area.x, y: area.y + area.height / 2, width: area.width / 2, height: area.height / 2 }, gap);
    case "bottom-right":
      return addGap({ x: area.x + area.width / 2, y: area.y + area.height / 2, width: area.width / 2, height: area.height / 2 }, gap);
    case "first-third":
      return addGap({ x: area.x, y: area.y, width: area.width / 3, height: area.height }, gap);
    case "center-third":
      return addGap({ x: area.x + area.width / 3, y: area.y, width: area.width / 3, height: area.height }, gap);
    case "last-third":
      return addGap({ x: area.x + (area.width * 2) / 3, y: area.y, width: area.width / 3, height: area.height }, gap);
    case "two-thirds-left":
      return addGap({ x: area.x, y: area.y, width: (area.width * 2) / 3, height: area.height }, gap);
    case "two-thirds-right":
      return addGap({ x: area.x + area.width / 3, y: area.y, width: (area.width * 2) / 3, height: area.height }, gap);
  }
}

export async function copyActiveWindowDebugInfo(): Promise<void> {
  try {
    const ctx = await getActiveWindowContext();
    const debugInfo = {
      timestamp: new Date().toISOString(),
      internalSetWindowBoundsAvailable: hasInternalSetWindowBounds(),
      window: ctx.window,
      selectedScreen: ctx.screen,
      workArea: ctx.workArea,
      screens: ctx.screens,
      preferences: getWindowPreferences(),
    };
    const debugText = JSON.stringify(debugInfo, null, 2);

    console.log("Vicinae window-management debug", debugText);
    await Clipboard.copy(debugText);
    await sendDesktopNotification({
      title: "Vicinae window debug copied",
      body: `${ctx.window.application?.name ?? ctx.window.title} on ${ctx.screen.name}`,
    });
  } catch (error) {
    console.error("Vicinae window-management debug failed", error);
    await sendDesktopNotification({
      title: "Vicinae window debug failed",
      body: error instanceof Error ? error.message : String(error),
    });
  }
}

export async function applyLayout(kind: LayoutKind): Promise<void> {
  try {
    const ctx = await getActiveWindowContext();
    await savePreviousBounds(ctx.window);
    await setWindowBounds(ctx.window, rectToBounds(computeLayout(kind, ctx)));
  } catch (error) {
    console.error(`Vicinae window layout failed (${kind})`, error);
    await showToast({
      style: Toast.Style.Failure,
      title: "Window layout failed",
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

export async function restorePreviousBounds(): Promise<void> {
  try {
    const ctx = await getActiveWindowContext();
    const stored = await LocalStorage.getItem<string>(storageKey(ctx.window));
    if (!stored) {
      throw new Error("No previous bounds saved for this window");
    }

    const previous = JSON.parse(stored) as Rect;
    await setWindowBounds(ctx.window, rectToBounds(previous));
  } catch (error) {
    console.error("Vicinae restore previous bounds failed", error);
    await showToast({
      style: Toast.Style.Failure,
      title: "Restore failed",
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

export async function moveToNextDisplay(): Promise<void> {
  try {
    const ctx = await getActiveWindowContext();
    if (ctx.screens.length < 2) {
      throw new Error("Only one display is connected");
    }

    const preferences = getWindowPreferences();
    const currentScreenIndex = ctx.screens.indexOf(ctx.screen);
    const nextScreen = ctx.screens[(currentScreenIndex + 1) % ctx.screens.length];
    const currentArea = ctx.workArea;
    const nextArea = insetRect(screenToRect(nextScreen), {
      top: preferences.paddingTop,
      bottom: preferences.paddingBottom,
      left: preferences.paddingLeft,
      right: preferences.paddingRight,
    });

    const current = boundsToRect(ctx.window.bounds);
    const relativeX = currentArea.width === 0 ? 0 : (current.x - currentArea.x) / currentArea.width;
    const relativeY = currentArea.height === 0 ? 0 : (current.y - currentArea.y) / currentArea.height;
    const target = clampRectToArea(
      {
        x: nextArea.x + relativeX * nextArea.width,
        y: nextArea.y + relativeY * nextArea.height,
        width: Math.min(current.width, nextArea.width),
        height: Math.min(current.height, nextArea.height),
      },
      nextArea,
    );

    await savePreviousBounds(ctx.window);
    await setWindowBounds(ctx.window, rectToBounds(target));
  } catch (error) {
    console.error("Vicinae move to next display failed", error);
    await showToast({
      style: Toast.Style.Failure,
      title: "Move to display failed",
      message: error instanceof Error ? error.message : String(error),
    });
  }
}
