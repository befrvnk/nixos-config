import { spawnSync } from "node:child_process";
import { accessSync, constants } from "node:fs";
import path from "node:path";

export const DEFAULT_COMMAND_PACKAGE_MAP = Object.freeze({
	bun: "bun",
	cargo: ["cargo", "rustc"],
	corepack: "nodejs",
	fd: "fd",
	go: "go",
	jq: "jq",
	node: "nodejs",
	npm: "nodejs",
	npx: "nodejs",
	pip: "python3",
	pip3: "python3",
	pnpm: "nodejs",
	python: "python3",
	python3: "python3",
	rg: "ripgrep",
	rustc: "rustc",
	shellcheck: "shellcheck",
	shfmt: "shfmt",
	uv: "uv",
	yarn: "nodejs",
	yq: "yq-go",
});

const COMMAND_PREFIX_TOKENS = new Set(["builtin", "command", "env", "noglob", "time"]);
const CONTROL_OPERATORS = new Set(["&&", "(", ")", ";", "|", "||", "\n", "&"]);
const REDIRECTION_PATTERN = /^\d*(?:>>?|<<?|&>>?|&>|<>).*$/;
const ASSIGNMENT_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*=.*/;
const SHELL_COMMAND_NAMES = new Set(["bash", "dash", "fish", "nu", "sh", "zsh"]);
const DARWIN_DEVELOPER_TOOL_SHIMS = new Set(["pip", "pip3", "python", "python3"]);
const FIND_EXEC_TOKENS = new Set(["-exec", "-execdir"]);
const FIND_EXEC_TERMINATORS = new Set([";", "\\;", "+"]);
const XARGS_OPTIONS_WITH_VALUES = new Set([
	"-a",
	"-d",
	"-E",
	"-e",
	"-I",
	"-i",
	"-L",
	"-l",
	"-n",
	"-P",
	"-s",
	"-S",
	"--arg-file",
	"--delimiter",
	"--eof",
	"--eof-string",
	"--max-args",
	"--max-chars",
	"--max-lines",
	"--max-procs",
	"--open-tty",
	"--replace",
]);
const availabilityCache = new Map();

function xcrunFind(command, env) {
	const result = spawnSync("/usr/bin/xcrun", ["-find", command], {
		env: { ...process.env, ...env },
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
		timeout: 1000,
	});

	return !result.error && result.status === 0 && result.stdout.trim().length > 0;
}

export function isUnavailableDarwinDeveloperToolShim(
	command,
	candidate,
	{
		env = process.env,
		platform = process.platform,
		runXcrunFind = xcrunFind,
	} = {},
) {
	if (platform !== "darwin") return false;
	if (!DARWIN_DEVELOPER_TOOL_SHIMS.has(command)) return false;
	if (path.normalize(candidate) !== path.join("/usr/bin", command)) return false;
	return !runXcrunFind(command, env);
}

function splitCommandTokens(command) {
	const tokens = [];
	let current = "";
	let state = "normal";
	let escaped = false;

	const pushCurrent = () => {
		if (!current) return;
		tokens.push(current);
		current = "";
	};

	for (let i = 0; i < command.length; i += 1) {
		const char = command[i];
		const next = command[i + 1];

		if (state === "single") {
			current += char;
			if (char === "'") state = "normal";
			continue;
		}

		if (state === "double") {
			current += char;
			if (escaped) {
				escaped = false;
				continue;
			}
			if (char === "\\") {
				escaped = true;
				continue;
			}
			if (char === '"') state = "normal";
			continue;
		}

		if (char === "'") {
			current += char;
			state = "single";
			continue;
		}

		if (char === '"') {
			current += char;
			state = "double";
			continue;
		}

		if (char === "\\") {
			current += char;
			if (next !== undefined) {
				i += 1;
				current += command[i];
			}
			continue;
		}

		if (char === "#") {
			pushCurrent();
			while (i + 1 < command.length && command[i + 1] !== "\n") {
				i += 1;
			}
			continue;
		}

		if (char === "\n") {
			pushCurrent();
			tokens.push("\n");
			continue;
		}

		if (/\s/.test(char)) {
			pushCurrent();
			continue;
		}

		if (char === "|" || char === "&") {
			pushCurrent();
			if (next === char) {
				tokens.push(char + next);
				i += 1;
			} else {
				tokens.push(char);
			}
			continue;
		}

		if (char === ";" || char === "(" || char === ")") {
			pushCurrent();
			tokens.push(char);
			continue;
		}

		current += char;
	}

	pushCurrent();
	return tokens;
}

function splitIntoSegments(tokens) {
	const segments = [];
	let current = [];

	const pushCurrent = () => {
		if (current.length === 0) return;
		segments.push(current);
		current = [];
	};

	for (const token of tokens) {
		if (CONTROL_OPERATORS.has(token)) {
			pushCurrent();
			continue;
		}
		current.push(token);
	}

	pushCurrent();
	return segments;
}

function stripCommandPrefixToken(token) {
	if (!token) return token;

	let result = token;
	while (result.startsWith("--")) {
		const trimmed = result.slice(2);
		if (!trimmed) break;
		result = trimmed;
	}
	return result;
}

function normalizeExecutableName(token) {
	if (!token) return token;
	const normalized = stripCommandPrefixToken(token);
	if (!normalized) return normalized;
	if (!isPathLike(normalized)) return normalized;
	return path.basename(normalized.replace(/\\/g, "/"));
}

function unquoteToken(token) {
	if (!token || token.length < 2) return token;

	const quote = token[0];
	if ((quote !== "'" && quote !== '"') || token[token.length - 1] !== quote) return token;
	const inner = token.slice(1, -1);
	if (quote === "'") return inner;
	return inner.replace(/\\([\\"$`])/g, "$1");
}

function isPathLike(token) {
	return token.startsWith("./") || token.startsWith("../") || token.startsWith("/") || token.includes("/");
}

function isShellMetaToken(token) {
	return REDIRECTION_PATTERN.test(token);
}

export function isCommandOnPath(command, env = process.env) {
	if (!command) return false;
	if (isPathLike(command)) return true;

	const pathValue = env.PATH ?? "";
	const cacheKey = `${pathValue}::${env.DEVELOPER_DIR ?? ""}::${command}`;
	const cached = availabilityCache.get(cacheKey);
	if (cached !== undefined) return cached;

	const extensions = process.platform === "win32"
		? (env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD")
			.split(";")
			.filter(Boolean)
		: [""];

	for (const directory of pathValue.split(path.delimiter)) {
		if (!directory) continue;
		for (const extension of extensions) {
			const candidate = path.join(directory, `${command}${extension}`);
			try {
				accessSync(candidate, constants.X_OK);
				if (isUnavailableDarwinDeveloperToolShim(command, candidate, { env })) continue;
				availabilityCache.set(cacheKey, true);
				return true;
			} catch {
				// Keep looking.
			}
		}
	}

	availabilityCache.set(cacheKey, false);
	return false;
}

function normalizePackageList(value) {
	if (!value) return [];
	return Array.isArray(value) ? value : [value];
}

function addUniquePackages(packages, seenPackages, values) {
	for (const packageName of normalizePackageList(values)) {
		if (seenPackages.has(packageName)) continue;
		seenPackages.add(packageName);
		packages.push(packageName);
	}
}

function expandEnvironmentValue(value, env) {
	return value.replace(/\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))/g, (_match, bracedName, bareName) => {
		const name = bracedName ?? bareName;
		return env[name] ?? "";
	});
}

function applyEnvironmentAssignment(env, token) {
	const equalsIndex = token.indexOf("=");
	if (equalsIndex === -1) return env;

	const name = token.slice(0, equalsIndex);
	const rawValue = token.slice(equalsIndex + 1);
	return {
		...env,
		[name]: expandEnvironmentValue(rawValue, env),
	};
}

export function getMappedPackagesForExecutable(
	executable,
	{
		packageMap = DEFAULT_COMMAND_PACKAGE_MAP,
		isCommandAvailable = isCommandOnPath,
		env = process.env,
	} = {},
) {
	if (!executable) return [];
	if (isPathLike(executable)) return [];

	const mappedPackages = normalizePackageList(packageMap[executable]);
	if (mappedPackages.length === 0) return [];
	if (isCommandAvailable(executable, env)) return [];
	return mappedPackages;
}

function createCollectionState(options = {}) {
	return {
		packageMap: options.packageMap ?? DEFAULT_COMMAND_PACKAGE_MAP,
		isCommandAvailable: options.isCommandAvailable ?? isCommandOnPath,
		env: options.env ?? process.env,
		packages: [],
		seenPackages: new Set(),
	};
}

function withEnvironment(state, env) {
	return { ...state, env };
}

function findShellCommandStringTokenIndex(tokens, startIndex) {
	for (let index = startIndex; index < tokens.length; index += 1) {
		const token = tokens[index];
		if (!token) continue;
		if (token === "--") continue;
		if (token === "-c" || token === "--command" || (/^-[A-Za-z]*c[A-Za-z]*$/.test(token) && token !== "-s")) {
			return index + 1 < tokens.length ? index + 1 : undefined;
		}
		if (!token.startsWith("-")) return undefined;
	}
	return undefined;
}

function nextXargsCommandIndex(tokens, startIndex) {
	for (let index = startIndex; index < tokens.length; index += 1) {
		const token = tokens[index];
		if (!token) continue;
		if (token === "--") return index + 1 < tokens.length ? index + 1 : undefined;
		if (!token.startsWith("-")) return index;

		const [optionName, inlineValue] = token.split("=", 2);
		if (inlineValue !== undefined) continue;
		if (XARGS_OPTIONS_WITH_VALUES.has(optionName) && index + 1 < tokens.length) {
			index += 1;
		}
	}
	return undefined;
}

function findExecCommandGroups(tokens) {
	const groups = [];

	for (let index = 0; index < tokens.length; index += 1) {
		if (!FIND_EXEC_TOKENS.has(tokens[index])) continue;
		const start = index + 1;
		let end = start;
		while (end < tokens.length && !FIND_EXEC_TERMINATORS.has(tokens[end])) {
			end += 1;
		}
		if (start < end) groups.push(tokens.slice(start, end));
		index = end;
	}

	return groups;
}

function collectMappedPackagesFromSegment(tokens, state, depth = 0) {
	if (depth > 4 || tokens.length === 0) return;

	let commandIndex;
	let commandToken;
	let commandName;
	let commandEnv = state.env;

	for (let index = 0; index < tokens.length; index += 1) {
		const token = tokens[index];
		if (!token || isShellMetaToken(token)) continue;
		if (ASSIGNMENT_PATTERN.test(token)) {
			commandEnv = applyEnvironmentAssignment(commandEnv, token);
			continue;
		}

		const normalizedToken = stripCommandPrefixToken(token);
		if (COMMAND_PREFIX_TOKENS.has(normalizedToken)) continue;

		commandIndex = index;
		commandToken = normalizedToken;
		commandName = normalizeExecutableName(normalizedToken);
		addUniquePackages(
			state.packages,
			state.seenPackages,
			getMappedPackagesForExecutable(normalizedToken, withEnvironment(state, commandEnv)),
		);
		break;
	}

	if (commandIndex === undefined || !commandToken || !commandName) return;

	if (SHELL_COMMAND_NAMES.has(commandName)) {
		const scriptIndex = findShellCommandStringTokenIndex(tokens, commandIndex + 1);
		const scriptToken = scriptIndex !== undefined ? tokens[scriptIndex] : undefined;
		const script = unquoteToken(scriptToken);
		if (script) collectMappedPackagesFromCommand(script, withEnvironment(state, commandEnv), depth + 1);
		return;
	}

	if (commandName === "xargs") {
		const nestedIndex = nextXargsCommandIndex(tokens, commandIndex + 1);
		if (nestedIndex !== undefined) {
			collectMappedPackagesFromSegment(tokens.slice(nestedIndex), withEnvironment(state, commandEnv), depth + 1);
		}
		return;
	}

	if (commandName === "find") {
		for (const group of findExecCommandGroups(tokens.slice(commandIndex + 1))) {
			collectMappedPackagesFromSegment(group, withEnvironment(state, commandEnv), depth + 1);
		}
	}
}

function collectMappedPackagesFromCommand(command, state, depth = 0) {
	for (const segment of splitIntoSegments(splitCommandTokens(command))) {
		collectMappedPackagesFromSegment(segment, state, depth);
	}
}

export function getMappedPackagesForCommand(
	command,
	{
		packageMap = DEFAULT_COMMAND_PACKAGE_MAP,
		isCommandAvailable = isCommandOnPath,
		env = process.env,
		extraPackages = [],
	} = {},
) {
	const trimmed = command.trim();
	if (!trimmed) return [];
	if (/^nix\s+(shell|develop|run)\b/.test(trimmed)) return [];

	const state = createCollectionState({ packageMap, isCommandAvailable, env });
	collectMappedPackagesFromCommand(command, state);
	addUniquePackages(state.packages, state.seenPackages, extraPackages);
	return state.packages;
}

export function quoteForBash(command) {
	return `'${command.replace(/'/g, `'"'"'`)}'`;
}

export function rewriteCommandForNixShell(command, options = {}) {
	const packages = getMappedPackagesForCommand(command, options);
	if (packages.length === 0) return null;

	const packageArgs = packages.map((packageName) => `nixpkgs#${packageName}`).join(" ");
	return `nix shell ${packageArgs} --command bash -lc ${quoteForBash(command)}`;
}
