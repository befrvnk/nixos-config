import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import {
	createBashTool,
	createLocalBashOperations,
} from "@mariozechner/pi-coding-agent";
import { Text } from "@mariozechner/pi-tui";
import { rewriteCommandForNixShell } from "./rewrite.mjs";
import { shouldRegisterBashTool } from "./session.ts";

function formatBashCall(command: string, timeout: number | undefined, rewritten: string | null, theme: any) {
	let text = theme.fg("toolTitle", theme.bold("$ "));
	text += theme.fg("accent", command);
	if (timeout) {
		text += theme.fg("dim", ` (timeout ${timeout}s)`);
	}
	if (rewritten) {
		text += `\n${theme.fg("muted", "original:")} ${theme.fg("accent", command)}`;
		text += `\n${theme.fg("muted", "rewritten:")} ${theme.fg("dim", rewritten)}`;
	}
	return new Text(text, 0, 0);
}

export function createNixShellFallbackBashTool(cwd: string) {
	const bashTool = createBashTool(cwd, {
		spawnHook: ({ command, cwd, env }) => ({
			command: rewriteCommandForNixShell(command) ?? command,
			cwd,
			env,
		}),
	});

	return {
		...bashTool,
		execute: async (toolCallId, params, signal, onUpdate) => {
			return bashTool.execute(toolCallId, params, signal, onUpdate);
		},
		renderCall(args, theme) {
			const rewritten = rewriteCommandForNixShell(args.command);
			return formatBashCall(args.command, args.timeout, rewritten, theme);
		},
	};
}

export default function nixShellFallbackExtension(pi: ExtensionAPI) {
	let registeredCwd: string | undefined;
	const localBash = createLocalBashOperations();

	pi.on("session_start", (_event, ctx) => {
		if (!shouldRegisterBashTool(registeredCwd, ctx.cwd)) return;
		pi.registerTool(createNixShellFallbackBashTool(ctx.cwd));
		registeredCwd = ctx.cwd;
	});

	pi.on("user_bash", (event) => {
		const rewritten = rewriteCommandForNixShell(event.command);
		if (!rewritten) return undefined;

		return {
			operations: {
				exec(_command, cwd, options) {
					return localBash.exec(rewritten, cwd, options);
				},
			},
		};
	});
}
