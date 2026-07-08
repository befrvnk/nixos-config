import { copyActiveWindowDebugInfo } from "./lib/geometry";

export default async function DebugActiveWindow() {
  await copyActiveWindowDebugInfo();
}
