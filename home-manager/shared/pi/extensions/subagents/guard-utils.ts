import path from "node:path";

// This is intentionally a small, generic guard.
//
// It is not repo-bound and it is not a full sandbox. Its job is to keep
// subagents on read-only inspection tasks and away from obviously irrelevant
// runtime/system paths.
const SUSPICIOUS_PATH_PREFIXES = ["/$bunfs", "/dev", "/etc", "/proc", "/root", "/sys"];
const PATH_REFERENCE_REGEX = /@?(?:\.\.\/|\.\/|\/)[^\s'"`|;&()<>]+/g;
const DISALLOWED_FIND_ACTIONS = new Set([
  "-delete",
  "-exec",
  "-execdir",
  "-fls",
  "-fprint",
  "-fprint0",
  "-fprintf",
  "-ok",
  "-okdir",
]);
const READ_ONLY_BASH_COMMANDS = new Set([
  "basename",
  "cat",
  "cut",
  "dirname",
  "du",
  "fd",
  "file",
  "find",
  "git",
  "grep",
  "head",
  "ls",
  "pwd",
  "readlink",
  "realpath",
  "rg",
  "sed",
  "sort",
  "stat",
  "tail",
  "tree",
  "uniq",
  "wc",
  "which",
]);
const READ_ONLY_GIT_SUBCOMMANDS = new Set([
  "blame",
  "branch",
  "cat-file",
  "describe",
  "diff",
  "grep",
  "log",
  "ls-files",
  "ls-tree",
  "merge-base",
  "name-rev",
  "remote",
  "rev-parse",
  "show",
  "status",
  "tag",
]);

export function stripAtPrefix(value: string): string {
  return value.startsWith("@") ? value.slice(1) : value;
}

export function isAllowedDevicePath(value: string): boolean {
  return value === "/dev/null" || value.startsWith("/dev/null/");
}

export function normalizePathCandidate(
  value: unknown,
  cwd: string,
): string | undefined {
  if (typeof value !== "string") return undefined;

  const trimmed = stripAtPrefix(value.trim());
  if (!trimmed) return undefined;

  if (trimmed.startsWith("/")) return path.normalize(trimmed);
  if (trimmed.startsWith("./") || trimmed.startsWith("../")) {
    return path.resolve(cwd, trimmed);
  }
  return undefined;
}

export function isSuspiciousPath(value: unknown, cwd: string): boolean {
  const normalized = normalizePathCandidate(value, cwd);
  return Boolean(
    normalized &&
      !isAllowedDevicePath(normalized) &&
      SUSPICIOUS_PATH_PREFIXES.some(
        (prefix) => normalized === prefix || normalized.startsWith(`${prefix}/`),
      ),
  );
}

export function blockIfSuspiciousPath(
  toolName: string,
  input: Record<string, unknown>,
  cwd: string,
) {
  const pathValue = input.path ?? input.file_path;
  if (isSuspiciousPath(pathValue, cwd)) {
    return `${toolName} path references a blocked runtime or system path: ${String(pathValue)}`;
  }
  return undefined;
}

export function extractCommandPathCandidates(command: string): string[] {
  return command.match(PATH_REFERENCE_REGEX) ?? [];
}

export function tokenizeShellSegment(segment: string): string[] {
  return segment.match(/[^\s'"`|;&()<>]+/g) ?? [];
}

export function containsUnquotedCharacter(
  command: string,
  target: string,
): boolean {
  let inSingleQuote = false;
  let inDoubleQuote = false;
  let escaped = false;

  for (let i = 0; i < command.length; i++) {
    const char = command[i]!;

    if (escaped) {
      escaped = false;
      continue;
    }

    if (char === "\\" && !inSingleQuote) {
      escaped = true;
      continue;
    }

    if (char === "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      continue;
    }

    if (char === '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && char === target) return true;
  }

  return false;
}

export function containsUnquotedCommandSubstitution(command: string): boolean {
  let inSingleQuote = false;
  let inDoubleQuote = false;
  let escaped = false;

  for (let i = 0; i < command.length; i++) {
    const char = command[i]!;

    if (escaped) {
      escaped = false;
      continue;
    }

    if (char === "\\" && !inSingleQuote) {
      escaped = true;
      continue;
    }

    if (char === "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      continue;
    }

    if (char === '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      continue;
    }

    if (!inSingleQuote && char === "`") return true;
    if (!inSingleQuote && char === "$" && command[i + 1] === "(") return true;
  }

  return false;
}

export function splitShellSegments(command: string): string[] {
  const segments: string[] = [];
  let current = "";
  let inSingleQuote = false;
  let inDoubleQuote = false;
  let escaped = false;

  for (let i = 0; i < command.length; i++) {
    const char = command[i]!;
    const next = command[i + 1];

    if (escaped) {
      current += char;
      escaped = false;
      continue;
    }

    if (char === "\\" && !inSingleQuote) {
      current += char;
      escaped = true;
      continue;
    }

    if (char === "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      current += char;
      continue;
    }

    if (char === '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      current += char;
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote) {
      const doubleOperator = `${char}${next ?? ""}`;
      if (doubleOperator === "&&" || doubleOperator === "||") {
        if (current.trim()) segments.push(current.trim());
        current = "";
        i += 1;
        continue;
      }

      if (char === ";" || char === "|" || char === "&") {
        if (current.trim()) segments.push(current.trim());
        current = "";
        continue;
      }
    }

    current += char;
  }

  if (current.trim()) segments.push(current.trim());
  return segments;
}

export function stripLeadingEnvironmentAssignments(tokens: string[]): string[] {
  let index = 0;
  while (
    index < tokens.length &&
    /^[A-Za-z_][A-Za-z0-9_]*=.*/.test(tokens[index]!)
  ) {
    index++;
  }
  return tokens.slice(index);
}

export function getExecutableAndArgs(segment: string): string[] {
  let tokens = stripLeadingEnvironmentAssignments(tokenizeShellSegment(segment));

  while (tokens[0] === "env") {
    tokens = stripLeadingEnvironmentAssignments(tokens.slice(1));
  }

  return tokens;
}

export function getGitSubcommand(args: string[]): string | undefined {
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!;
    if (
      arg === "-c" ||
      arg === "-C" ||
      arg === "--git-dir" ||
      arg === "--work-tree" ||
      arg === "--namespace"
    ) {
      i += 1;
      continue;
    }
    if (arg.startsWith("-")) continue;
    return arg;
  }
  return undefined;
}

function hasBlockedOption(args: string[], exact: string[], prefixes: string[] = []): boolean {
  return args.some((arg) => exact.includes(arg) || prefixes.some((prefix) => arg.startsWith(prefix)));
}

function validateReadOnlyGit(args: string[]): string | undefined {
  const riskyGlobal = ["-c", "-C", "--config-env", "--git-dir", "--work-tree", "--namespace"];
  if (hasBlockedOption(args, riskyGlobal, riskyGlobal.map((option) => `${option}=`))) {
    return "bash does not allow git configuration or repository redirection options in subagents.";
  }

  const normalized = args[0] === "--no-pager" ? args.slice(1) : args;
  const [subcommand, ...subcommandArgs] = normalized;
  if (!subcommand || subcommand.startsWith("-")) {
    return "bash requires an explicit read-only git subcommand in subagents.";
  }
  if (!READ_ONLY_GIT_SUBCOMMANDS.has(subcommand)) {
    return `bash only allows read-only git subcommands in subagents. Blocked subcommand: git ${subcommand}`;
  }

  if (hasBlockedOption(subcommandArgs, ["--ext-diff", "--textconv", "--open-files-in-pager", "--filters"], ["--output="])) {
    return "bash does not allow git options that execute helpers or write output in subagents.";
  }
  if (subcommandArgs.includes("--output")) {
    return "bash does not allow git options that write output in subagents.";
  }

  if (subcommand === "branch") {
    const allowed = new Set(["--list", "--show-current", "--all", "-a", "--remotes", "-r", "--verbose", "-v", "--no-color"]);
    if (subcommandArgs.some((arg) => !allowed.has(arg))) {
      return "bash only allows listing git branches in subagents.";
    }
  }
  if (subcommand === "tag") {
    const listing = subcommandArgs.length === 0 || subcommandArgs[0] === "--list" || subcommandArgs[0] === "-l";
    if (!listing) return "bash only allows listing git tags in subagents.";
  }
  if (subcommand === "remote" && subcommandArgs.some((arg) => arg !== "-v" && arg !== "--verbose")) {
    return "bash only allows listing git remotes in subagents.";
  }

  return undefined;
}

export function validateReadOnlyBashSegment(segment: string): string | undefined {
  const tokens = tokenizeShellSegment(segment);
  if (tokens.length === 0) return undefined;

  const [command, ...args] = tokens;
  if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(command)) {
    return "bash does not allow environment assignments in subagents.";
  }
  if (!READ_ONLY_BASH_COMMANDS.has(command)) {
    return `bash only allows read-only inspection commands in subagents. Blocked command: ${command}`;
  }

  if (command === "git") {
    const blocked = validateReadOnlyGit(args);
    if (blocked) return blocked;
  }

  if (command === "fd" && hasBlockedOption(args, ["-x", "-X", "--exec", "--exec-batch"], ["--exec=", "--exec-batch="])) {
    return "bash does not allow fd execution options in subagents.";
  }

  if (command === "rg" && hasBlockedOption(args, ["--pre", "--follow", "-L"], ["--pre="])) {
    return "bash does not allow rg preprocessor or symlink-following options in subagents.";
  }

  if (command === "find" && (args.includes("-L") || args.some((arg) => DISALLOWED_FIND_ACTIONS.has(arg)))) {
    return "bash does not allow find actions that execute, delete, or write files in subagents.";
  }

  if (
    command === "sed" &&
    args.some((arg) => arg === "-i" || arg === "-I" || /^-[iI].+/.test(arg) || arg === "--in-place" || arg.startsWith("--in-place="))
  ) {
    return "bash does not allow in-place sed edits in subagents.";
  }

  if (command === "sort" && hasBlockedOption(args, ["-o", "--output", "--compress-program"], ["-o", "--output=", "--compress-program="])) {
    return "bash does not allow sort output or compressor options in subagents.";
  }
  if (command === "tree" && hasBlockedOption(args, ["-o", "--output"], ["-o", "--output="])) {
    return "bash does not allow tree output options in subagents.";
  }
  if (command === "file" && hasBlockedOption(args, ["-C", "--compile"])) {
    return "bash does not allow file compilation options in subagents.";
  }

  return undefined;
}

function containsUnsafeShellSyntax(command: string): boolean {
  let inSingleQuote = false;
  let inDoubleQuote = false;
  let escaped = false;

  for (const char of command) {
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === "\\" && !inSingleQuote) {
      escaped = true;
      continue;
    }
    if (char === "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      continue;
    }
    if (char === '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      continue;
    }
    if (inSingleQuote) continue;
    if (char === "$" || char === "`") return true;
    if (!inDoubleQuote && ("\n\r;|&<>*?[".includes(char))) return true;
  }

  return inSingleQuote || inDoubleQuote || escaped;
}

export function blockIfSuspiciousBashCommand(command: unknown, cwd: string) {
  if (typeof command !== "string") return undefined;

  if (containsUnsafeShellSyntax(command)) {
    return "bash only allows one simple inspection command without shell expansion, composition, or redirection in subagents.";
  }

  const pathReferences = extractCommandPathCandidates(command);
  if (pathReferences.some((candidate) => isSuspiciousPath(candidate, cwd))) {
    return "bash command references blocked runtime or system paths";
  }

  return validateReadOnlyBashSegment(command);
}
