import type { WindowManagement } from "@vicinae/api";
import { getClient } from "@vicinae/api/dist/api/client";
import type { Rect } from "@vicinae/api/dist/api/proto/api";

export type Bounds = WindowManagement.Window["bounds"];

export function toRect(bounds: Bounds): Rect {
  return {
    x: Math.round(bounds.position.x),
    y: Math.round(bounds.position.y),
    width: Math.round(bounds.size.width),
    height: Math.round(bounds.size.height),
  };
}

/**
 * Temporary compatibility shim.
 *
 * Vicinae v0.23.0 exposes WindowManagement.setWindowBounds in the generated
 * extension RPC client, but not yet in the public WindowManagement wrapper.
 * Keep the deep import isolated here so this file can be replaced with the
 * official API once Vicinae publishes it.
 */
export async function setWindowBounds(window: WindowManagement.Window, bounds: Bounds): Promise<void> {
  await getClient().WindowManagement.setWindowBounds(window.id, toRect(bounds));
}
