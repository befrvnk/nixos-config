import assert from "node:assert/strict";
import test from "node:test";
import { createRetryingBashOperations, extractMissingCommandName } from "./runtime.ts";

test("extractMissingCommandName handles common shell error formats", () => {
	assert.equal(extractMissingCommandName("bash: line 1: rg: command not found"), "rg");
	assert.equal(extractMissingCommandName("xargs: rg: No such file or directory"), "rg");
	assert.equal(extractMissingCommandName("zsh: command not found: uv"), "uv");
});

test("createRetryingBashOperations retries with newly detected packages and preserves live output", async () => {
	const commands: string[] = [];
	const events: string[] = [];
	const operations = createRetryingBashOperations(
		{
			async exec(command, _cwd, options) {
				commands.push(command);
				events.push(`exec:${commands.length}`);
				if (commands.length === 1) {
					options.onData?.(Buffer.from("bash: line 1: custom-rg: command not found\n"));
					return { exitCode: 127 };
				}

				options.onData?.(Buffer.from("match\n"));
				return { exitCode: 0 };
			},
		},
		{
			packageMap: {
				"custom-rg": "ripgrep",
				python: "python3",
			},
		},
	);

	const result = await operations.exec("python script.py", "/repo", {
		onData(data) {
			events.push(`stream:${data.toString("utf8")}`);
		},
	});

	assert.deepEqual(commands, [
		"nix shell nixpkgs#python3 --command bash -lc 'python script.py'",
		"nix shell nixpkgs#python3 nixpkgs#ripgrep --command bash -lc 'python script.py'",
	]);
	assert.equal(result.exitCode, 0);
	assert.deepEqual(events, [
		"exec:1",
		"stream:bash: line 1: custom-rg: command not found\n",
		"exec:2",
		"stream:match\n",
	]);
});

test("createRetryingBashOperations stops when the missing command is unmapped", async () => {
	const commands: string[] = [];
	const operations = createRetryingBashOperations({
		async exec(command, _cwd, options) {
			commands.push(command);
			options.onData?.(Buffer.from("bash: line 1: custom-tool: command not found\n"));
			return { exitCode: 127 };
		},
	});

	const result = await operations.exec("python script.py", "/repo", { onData() {} });

	assert.deepEqual(commands, [
		"nix shell nixpkgs#python3 --command bash -lc 'python script.py'",
	]);
	assert.equal(result.exitCode, 127);
});

test("createRetryingBashOperations does not retry successful commands whose output matches an error pattern", async () => {
	const commands: string[] = [];
	const streamed: string[] = [];
	const operations = createRetryingBashOperations({
		async exec(command, _cwd, options) {
			commands.push(command);
			options.onData?.(Buffer.from("bash: line 1: rg: command not found\n"));
			return { exitCode: 0 };
		},
	});

	const result = await operations.exec("python script.py", "/repo", {
		onData(data) {
			streamed.push(data.toString("utf8"));
		},
	});

	assert.deepEqual(commands, [
		"nix shell nixpkgs#python3 --command bash -lc 'python script.py'",
	]);
	assert.equal(result.exitCode, 0);
	assert.deepEqual(streamed, ["bash: line 1: rg: command not found\n"]);
});

test("createRetryingBashOperations can retry even when static analysis finds no initial rewrite", async () => {
	const commands: string[] = [];
	const operations = createRetryingBashOperations(
		{
			async exec(command, _cwd, options) {
				commands.push(command);
				if (commands.length === 1) {
					options.onData?.(Buffer.from("bash: line 1: custom-rg: command not found\n"));
					return { exitCode: 127 };
				}
				options.onData?.(Buffer.from("ok\n"));
				return { exitCode: 0 };
			},
		},
		{
			packageMap: {
				"custom-rg": "ripgrep",
			},
		},
	);

	const result = await operations.exec("my-wrapper build", "/repo", { onData() {} });

	assert.deepEqual(commands, [
		"my-wrapper build",
		"nix shell nixpkgs#ripgrep --command bash -lc 'my-wrapper build'",
	]);
	assert.equal(result.exitCode, 0);
});
