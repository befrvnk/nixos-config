import {
  createBashTool,
  createFindTool,
  createGrepTool,
  createLsTool,
  createReadTool,
} from "@mariozechner/pi-coding-agent";
import {
  blockIfSuspiciousBashCommand,
  blockIfSuspiciousPath,
} from "./guard-utils.js";

function wrapGuardedTool(
  original: any,
  validate: (params: Record<string, unknown>) => string | undefined,
) {
  return {
    name: original.name,
    label: original.label,
    description: original.description,
    promptSnippet: original.promptSnippet,
    promptGuidelines: original.promptGuidelines,
    parameters: original.parameters,
    prepareArguments: original.prepareArguments?.bind(original),
    async execute(
      toolCallId: string,
      params: Record<string, unknown>,
      signal?: AbortSignal,
      onUpdate?: (update: any) => void,
      ctx?: any,
    ) {
      const blocked = validate(params);
      if (blocked) throw new Error(blocked);
      return original.execute(toolCallId, params, signal, onUpdate, ctx);
    },
    renderCall: original.renderCall?.bind(original),
    renderResult: original.renderResult?.bind(original),
  };
}

export { blockIfSuspiciousBashCommand, blockIfSuspiciousPath };

export function createGuardedExplorationTools(cwd: string) {
  return [
    wrapGuardedTool(createReadTool(cwd), (params) =>
      blockIfSuspiciousPath("read", params, cwd),
    ),
    wrapGuardedTool(createGrepTool(cwd), (params) =>
      blockIfSuspiciousPath("grep", params, cwd),
    ),
    wrapGuardedTool(createFindTool(cwd), (params) =>
      blockIfSuspiciousPath("find", params, cwd),
    ),
    wrapGuardedTool(createLsTool(cwd), (params) =>
      blockIfSuspiciousPath("ls", params, cwd),
    ),
    wrapGuardedTool(createBashTool(cwd), (params) =>
      blockIfSuspiciousBashCommand(params.command, cwd),
    ),
  ];
}
