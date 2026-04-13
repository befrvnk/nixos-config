import {
  createFindTool,
  createGrepTool,
  createLsTool,
  type ExtensionAPI,
  type ExtensionContext,
} from "@mariozechner/pi-coding-agent";

const NAVIGATION_TOOL_NAMES = ["grep", "find", "ls"] as const;

function ensureNavigationToolsActive(pi: ExtensionAPI) {
  const activeTools = new Set(pi.getActiveTools());
  for (const toolName of NAVIGATION_TOOL_NAMES) activeTools.add(toolName);
  pi.setActiveTools(Array.from(activeTools));
}

export default function navToolsExtension(pi: ExtensionAPI) {
  let registeredCwd: string | undefined;

  pi.on("session_start", async (_event: unknown, ctx: ExtensionContext) => {
    if (registeredCwd !== ctx.cwd) {
      pi.registerTool(createGrepTool(ctx.cwd));
      pi.registerTool(createFindTool(ctx.cwd));
      pi.registerTool(createLsTool(ctx.cwd));
      registeredCwd = ctx.cwd;
    }

    ensureNavigationToolsActive(pi);
  });
}
