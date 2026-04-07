import {
  createBashTool,
  createFindTool,
  createGrepTool,
  createLsTool,
  createReadTool,
} from "@mariozechner/pi-coding-agent";

// This is intentionally a small, generic denylist guard.
//
// It is not repo-bound and it is not a full sandbox. Its job is simply to stop
// the most common exploration failure mode we observed in practice: subagents
// drifting into execution-environment internals instead of staying on the user
// task. We only block obviously irrelevant runtime/system paths here so the
// extension remains usable for non-repo exploration tasks too.
const SUSPICIOUS_PATH_PREFIXES = ["/$bunfs", "/proc", "/sys", "/dev"];

function isAllowedDevicePath(value: string): boolean {
  return value === "/dev/null" || value.startsWith("/dev/null/");
}

function isSuspiciousPath(value: unknown): boolean {
  return typeof value === "string"
    && !isAllowedDevicePath(value)
    && SUSPICIOUS_PATH_PREFIXES.some((prefix) => value.startsWith(prefix));
}

export function blockIfSuspiciousPath(toolName: string, input: Record<string, unknown>) {
  const pathValue = input.path ?? input.file_path;
  if (isSuspiciousPath(pathValue)) {
    return `${toolName} path references a blocked runtime or system path: ${String(pathValue)}`;
  }
  return undefined;
}

export function blockIfSuspiciousBashCommand(command: unknown) {
  if (typeof command !== "string") return undefined;

  const pathReferences = command.match(/\/[^\s'"`|;&]+/g) ?? [];
  if (pathReferences.some((path) => isSuspiciousPath(path))) {
    return "bash command references blocked runtime or system paths";
  }

  return undefined;
}

function wrapGuardedTool(original: any, validate: (params: Record<string, unknown>) => string | undefined) {
  return {
    name: original.name,
    label: original.label,
    description: original.description,
    promptSnippet: original.promptSnippet,
    promptGuidelines: original.promptGuidelines,
    parameters: original.parameters,
    prepareArguments: original.prepareArguments?.bind(original),
    async execute(toolCallId: string, params: Record<string, unknown>, signal?: AbortSignal, onUpdate?: (update: any) => void, ctx?: any) {
      const blocked = validate(params);
      if (blocked) throw new Error(blocked);
      return original.execute(toolCallId, params, signal, onUpdate, ctx);
    },
    renderCall: original.renderCall?.bind(original),
    renderResult: original.renderResult?.bind(original),
  };
}

export function createGuardedExplorationTools(cwd: string) {
  return [
    wrapGuardedTool(createReadTool(cwd), (params) => blockIfSuspiciousPath("read", params)),
    wrapGuardedTool(createGrepTool(cwd), (params) => blockIfSuspiciousPath("grep", params)),
    wrapGuardedTool(createFindTool(cwd), (params) => blockIfSuspiciousPath("find", params)),
    wrapGuardedTool(createLsTool(cwd), (params) => blockIfSuspiciousPath("ls", params)),
    wrapGuardedTool(createBashTool(cwd), (params) => blockIfSuspiciousBashCommand(params.command)),
  ];
}

