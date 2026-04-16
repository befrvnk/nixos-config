import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const NAVIGATION_TOOL_NAMES = ["grep", "find", "ls"] as const;

function ensureNavigationToolsActive(pi: ExtensionAPI) {
  const activeTools = new Set(pi.getActiveTools());
  for (const toolName of NAVIGATION_TOOL_NAMES) activeTools.add(toolName);
  pi.setActiveTools(Array.from(activeTools));
}

export default function navToolsExtension(pi: ExtensionAPI) {
  pi.on("session_start", async () => {
    ensureNavigationToolsActive(pi);
  });
}
