import {
  createBashTool,
  createFindTool,
  createGrepTool,
  createLsTool,
  createReadTool,
} from "@earendil-works/pi-coding-agent";
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
    wrapGuardedTool(
      createBashTool(cwd, {
        spawnHook: ({ command, cwd: commandCwd, env }) => ({
          command,
          cwd: commandCwd,
          env: {
            ...env,
            GIT_CONFIG_COUNT: "3",
            GIT_CONFIG_KEY_0: "core.fsmonitor",
            GIT_CONFIG_VALUE_0: "false",
            GIT_CONFIG_KEY_1: "diff.external",
            GIT_CONFIG_VALUE_1: "",
            GIT_CONFIG_KEY_2: "core.pager",
            GIT_CONFIG_VALUE_2: "cat",
            GIT_EXTERNAL_DIFF: "",
            GIT_OPTIONAL_LOCKS: "0",
            GIT_PAGER: "cat",
            PAGER: "cat",
            RIPGREP_CONFIG_PATH: "",
          },
        }),
      }),
      (params) => blockIfSuspiciousBashCommand(params.command, cwd),
    ),
  ];
}
