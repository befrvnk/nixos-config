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
  tokenizeShellSegment,
} from "./guard-utils.js";
import { resolvePathWithinRoot } from "./path-security.js";

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

export function createGuardedExplorationTools(
  cwd: string,
  options: { restrictToRoot?: boolean } = {},
) {
  const validatePath = (toolName: string, params: Record<string, unknown>) => {
    const suspicious = blockIfSuspiciousPath(toolName, params, cwd);
    if (suspicious) return suspicious;
    if (!options.restrictToRoot) return undefined;
    const value = params.path ?? params.file_path;
    if (value === undefined) return undefined;
    if (typeof value !== "string" || !resolvePathWithinRoot(cwd, value)) {
      return `${toolName} path must remain within the review inspection root.`;
    }
    return undefined;
  };

  return [
    wrapGuardedTool(createReadTool(cwd), (params) =>
      validatePath("read", params),
    ),
    wrapGuardedTool(createGrepTool(cwd), (params) =>
      validatePath("grep", params),
    ),
    wrapGuardedTool(createFindTool(cwd), (params) =>
      validatePath("find", params),
    ),
    wrapGuardedTool(createLsTool(cwd), (params) =>
      validatePath("ls", params),
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
      (params) => {
        const blocked = blockIfSuspiciousBashCommand(params.command, cwd);
        if (blocked || !options.restrictToRoot || typeof params.command !== "string") return blocked;
        const command = tokenizeShellSegment(params.command)[0];
        return command === "git" || command === "pwd"
          ? undefined
          : "review subagents use structured tools for repository file inspection; bash is limited to git and pwd.";
      },
    ),
  ];
}
