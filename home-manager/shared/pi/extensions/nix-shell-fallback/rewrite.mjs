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
const CONTROL_OPERATORS = new Set(["&&", "(", ")", ";", "|", "||", "\n"]);
const REDIRECTION_PATTERN = /^\d*(?:>>?|<<?|&>>?|&>|<>).*$/;
const ASSIGNMENT_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*=.*/;
const availabilityCache = new Map();

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
	const cacheKey = `${pathValue}::${command}`;
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

export function getMappedPackagesForCommand(
	command,
	{
		packageMap = DEFAULT_COMMAND_PACKAGE_MAP,
		isCommandAvailable = isCommandOnPath,
	} = {},
) {
	const trimmed = command.trim();
	if (!trimmed) return [];
	if (/^nix\s+(shell|develop|run)\b/.test(trimmed)) return [];

	const packages = [];
	const seenPackages = new Set();
	let expectingCommand = true;

	for (const token of splitCommandTokens(command)) {
		if (CONTROL_OPERATORS.has(token)) {
			expectingCommand = true;
			continue;
		}

		if (!expectingCommand) continue;
		if (!token) continue;
		if (isShellMetaToken(token)) continue;
		if (ASSIGNMENT_PATTERN.test(token)) continue;

		const normalizedToken = stripCommandPrefixToken(token);
		if (COMMAND_PREFIX_TOKENS.has(normalizedToken)) continue;
		if (isPathLike(normalizedToken)) {
			expectingCommand = false;
			continue;
		}

		const mappedPackages = normalizePackageList(packageMap[normalizedToken]);
		if (mappedPackages.length > 0 && !isCommandAvailable(normalizedToken)) {
			for (const packageName of mappedPackages) {
				if (seenPackages.has(packageName)) continue;
				seenPackages.add(packageName);
				packages.push(packageName);
			}
		}

		expectingCommand = false;
	}

	return packages;
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
