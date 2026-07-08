import type { WindowManagement } from "@vicinae/api";

export type Bounds = WindowManagement.Window["bounds"];

type Rect = {
  x: number;
  y: number;
  width: number;
  height: number;
};

type VicinaeGlobal = typeof globalThis & {
  vicinae?: {
    client?: {
      WindowManagement?: {
        setWindowBounds(winId: string, bounds: Rect): Promise<void>;
      };
    };
  };
};

export function toRect(bounds: Bounds): Rect {
  const x = Math.round(bounds.position.x);
  const y = Math.round(bounds.position.y);
  const right = Math.round(bounds.position.x + bounds.size.width);
  const bottom = Math.round(bounds.position.y + bounds.size.height);

  return {
    x,
    y,
    width: Math.max(1, right - x),
    height: Math.max(1, bottom - y),
  };
}

/**
 * Temporary compatibility shim.
 *
 * Vicinae v0.23.0 exposes WindowManagement.setWindowBounds on the runtime
 * client, but not yet in the public WindowManagement wrapper. Avoid deep
 * imports because Vicinae's extension manager only shims the top-level
 * @vicinae/api module at runtime.
 */
export async function setWindowBounds(window: WindowManagement.Window, bounds: Bounds): Promise<void> {
  const client = (globalThis as VicinaeGlobal).vicinae?.client;
  const setBounds = client?.WindowManagement?.setWindowBounds;

  if (!setBounds) {
    throw new Error("Vicinae runtime does not expose WindowManagement.setWindowBounds");
  }

  await setBounds.call(client.WindowManagement, window.id, toRect(bounds));
}
