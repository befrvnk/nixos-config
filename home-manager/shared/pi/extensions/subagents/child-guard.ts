import path from "node:path";
import {
	createBashTool,
	createFindTool,
	createGrepTool,
	createLsTool,
	createReadTool,
} from "@mariozechner/pi-coding-agent";

// This is intentionally a small, generic guard.
//
// It is not repo-bound and it is not a full sandbox. Its job is to keep
// subagents on read-only inspection tasks and away from obviously irrelevant
// runtime/system paths.
const SUSPICIOUS_PATH_PREFIXES = ["/$bunfs", "/proc", "/sys", "/dev"];
const PATH_REFERENCE_REGEX = /(?:\.\.\/|\.\/|\/)[^\s'"`|;&()<>]+/g;
const READ_ONLY_BASH_COMMANDS = new Set([
	"basename",
	"cat",
	"cut",
	"dirname",
	"du",
	"echo",
	"env",
	"fd",
	"file",
	"find",
	"git",
	"grep",
	"head",
	"ls",
	"pwd",
	"printf",
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

function stripAtPrefix(value: string): string {
	return value.startsWith("@") ? value.slice(1) : value;
}

function isAllowedDevicePath(value: string): boolean {
	return value === "/dev/null" || value.startsWith("/dev/null/");
}

function normalizePathCandidate(
	value: unknown,
	cwd: string,
): string | undefined {
	if (typeof value !== "string") return undefined;

	const trimmed = stripAtPrefix(value.trim());
	if (!trimmed) return undefined;

	if (trimmed.startsWith("/")) return path.normalize(trimmed);
	if (trimmed.startsWith("./") || trimmed.startsWith("../"))
		return path.resolve(cwd, trimmed);
	return undefined;
}

function isSuspiciousPath(value: unknown, cwd: string): boolean {
	const normalized = normalizePathCandidate(value, cwd);
	return Boolean(
		normalized &&
			!isAllowedDevicePath(normalized) &&
			SUSPICIOUS_PATH_PREFIXES.some((prefix) => normalized.startsWith(prefix)),
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

function extractCommandPathCandidates(command: string): string[] {
	return command.match(PATH_REFERENCE_REGEX) ?? [];
}

function tokenizeShellSegment(segment: string): string[] {
	return segment.match(/[^\s'"`|;&()<>]+/g) ?? [];
}

function containsUnquotedCharacter(command: string, target: string): boolean {
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

function containsUnquotedCommandSubstitution(command: string): boolean {
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

function splitShellSegments(command: string): string[] {
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

			if (char === ";" || char === "|") {
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

function stripLeadingEnvironmentAssignments(tokens: string[]): string[] {
	let index = 0;
	while (
		index < tokens.length &&
		/^[A-Za-z_][A-Za-z0-9_]*=.*/.test(tokens[index]!)
	)
		index++;
	return tokens.slice(index);
}

function getExecutableAndArgs(segment: string): string[] {
	let tokens = stripLeadingEnvironmentAssignments(
		tokenizeShellSegment(segment),
	);

	while (tokens[0] === "env") {
		tokens = stripLeadingEnvironmentAssignments(tokens.slice(1));
	}

	return tokens;
}

function getGitSubcommand(args: string[]): string | undefined {
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

function validateReadOnlyBashSegment(segment: string): string | undefined {
	const tokens = getExecutableAndArgs(segment);
	if (tokens.length === 0) return undefined;

	const [command, ...args] = tokens;
	if (!READ_ONLY_BASH_COMMANDS.has(command)) {
		return `bash only allows read-only inspection commands in subagents. Blocked command: ${command}`;
	}

	if (command === "git") {
		const subcommand = getGitSubcommand(args);
		if (subcommand && !READ_ONLY_GIT_SUBCOMMANDS.has(subcommand)) {
			return `bash only allows read-only git subcommands in subagents. Blocked subcommand: git ${subcommand}`;
		}
	}

	if (
		command === "sed" &&
		tokens.some((arg) => arg === "-i" || /^-i.+/.test(arg))
	) {
		return "bash does not allow in-place sed edits in subagents.";
	}

	return undefined;
}

export function blockIfSuspiciousBashCommand(command: unknown, cwd: string) {
	if (typeof command !== "string") return undefined;

	if (containsUnquotedCommandSubstitution(command)) {
		return "bash does not allow command substitution in subagents.";
	}

	if (containsUnquotedCharacter(command, ">")) {
		return "bash does not allow output redirection in subagents.";
	}

	const pathReferences = extractCommandPathCandidates(command);
	if (pathReferences.some((candidate) => isSuspiciousPath(candidate, cwd))) {
		return "bash command references blocked runtime or system paths";
	}

	const segments = splitShellSegments(command);
	for (const segment of segments) {
		const blocked = validateReadOnlyBashSegment(segment);
		if (blocked) return blocked;
	}

	return undefined;
}

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
