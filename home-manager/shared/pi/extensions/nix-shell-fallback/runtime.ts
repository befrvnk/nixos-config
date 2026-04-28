import {
	DEFAULT_COMMAND_PACKAGE_MAP,
	getMappedPackagesForExecutable,
	rewriteCommandForNixShell,
} from "./rewrite.mjs";

export type BashExecOptions = {
	onData?: (data: Buffer) => void;
	signal?: AbortSignal;
	timeout?: number;
};

export type BashExecResult = {
	exitCode?: number | null;
};

export type BashOperationsLike = {
	exec(command: string, cwd: string, options: BashExecOptions): Promise<BashExecResult>;
};

const MISSING_COMMAND_PATTERNS = [
	/\berror:\s+tool\s+['"`]?([^'"`\s:;]+)['"`]?\s+not found\b/gi,
	/\bcommand not found:\s*['"`]?([^'"`\s:;]+)['"`]?/gi,
	/\b(?:bash|dash|env|fish|find|nu|sh|xargs|zsh):(?: line \d+:)?\s+['"`]?([^'"`\s:;]+)['"`]?:\s+command not found\b/gi,
	/\b(?:bash|dash|fish|nu|sh|zsh):(?: line \d+:)?\s+['"`]?([^'"`\s:;]+)['"`]?:\s+not found\b/gi,
	/\b(?:env|find|xargs):\s+['"`]?([^'"`\s:;]+)['"`]?:\s+No such file or directory\b/gi,
	/(?:^|\n)\s*['"`]?([^'"`\s:;]+)['"`]?:\s+command not found\b/gi,
];

function toBuffer(chunk: Buffer | string) {
	return Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
}

export function extractMissingCommandName(output: string) {
	let candidate: string | undefined;

	for (const pattern of MISSING_COMMAND_PATTERNS) {
		pattern.lastIndex = 0;
		for (const match of output.matchAll(pattern)) {
			candidate = match[1] ?? candidate;
		}
		if (candidate) break;
	}

	return candidate;
}

export function createRetryingBashOperations(
	baseOperations: BashOperationsLike,
	{
		maxRetries = 2,
		packageMap = DEFAULT_COMMAND_PACKAGE_MAP,
	}: {
		maxRetries?: number;
		packageMap?: Record<string, string | string[]>;
	} = {},
): BashOperationsLike {
	return {
		async exec(command, cwd, options) {
			const initialRewrite = rewriteCommandForNixShell(command, { packageMap });

			const extraPackages: string[] = [];
			const seenRetryPackages = new Set<string>();
			let lastResult: BashExecResult = { exitCode: undefined };

			for (let attempt = 0; attempt <= maxRetries; attempt += 1) {
				const rewritten = attempt === 0
					? initialRewrite
					: rewriteCommandForNixShell(command, {
						packageMap,
						extraPackages,
					});
				const commandToRun = rewritten ?? command;
				const chunks: Buffer[] = [];

				const result = await baseOperations.exec(commandToRun, cwd, {
					...options,
					onData(data) {
						const buffer = toBuffer(data);
						chunks.push(buffer);
						options.onData?.(buffer);
					},
				});

				lastResult = result;
				if (result.exitCode == null || result.exitCode === 0) break;

				const output = Buffer.concat(chunks).toString("utf8");
				const missingCommand = extractMissingCommandName(output);
				if (!missingCommand) break;

				const retryPackages = getMappedPackagesForExecutable(missingCommand, {
					packageMap,
					isCommandAvailable: () => false,
				});
				const newPackages = retryPackages.filter((packageName) => !seenRetryPackages.has(packageName));
				if (newPackages.length === 0) break;
				if (attempt >= maxRetries) break;

				for (const packageName of newPackages) {
					seenRetryPackages.add(packageName);
					extraPackages.push(packageName);
				}
			}

			return lastResult;
		},
	};
}
