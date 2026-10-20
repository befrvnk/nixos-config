import type { WindowManagement } from "@vicinae/api";
import { execFile } from "node:child_process";

export type Bounds = WindowManagement.Window["bounds"];

type Rect = {
  x: number;
  y: number;
  width: number;
  height: number;
};

export type VicinaeGlobal = typeof globalThis & {
  vicinae?: {
    client?: {
      WindowManagement?: {
        setWindowBounds(winId: string, bounds: Rect): Promise<void>;
      };
    };
  };
};

export function getInternalWindowManagementClient() {
  return (globalThis as VicinaeGlobal).vicinae?.client?.WindowManagement;
}

export function hasInternalSetWindowBounds(): boolean {
  return typeof getInternalWindowManagementClient()?.setWindowBounds === "function";
}

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

export async function executeRectangleAction(action: string): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    execFile(
      "/usr/bin/open",
      ["-g", `rectangle://execute-action?name=${action}`],
      (error, _stdout, stderr) => {
        if (!error) {
          resolve();
          return;
        }

        reject(new Error(stderr.trim() || error.message));
      },
    );
  });
}
