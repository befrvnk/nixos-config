import test from "node:test";
import assert from "node:assert/strict";
import {
	getMappedPackagesForCommand,
	quoteForBash,
	rewriteCommandForNixShell,
} from "./rewrite.mjs";

function unavailableCommands(...commands) {
	const missing = new Set(commands);
	return (command) => !missing.has(command);
}

test("maps python to python3 when python is missing", () => {
	assert.deepEqual(
		getMappedPackagesForCommand("python -c 'print(123)'", {
			isCommandAvailable: unavailableCommands("python"),
		}),
		["python3"],
	);
});

test("collects packages across pipelines", () => {
	assert.deepEqual(
		getMappedPackagesForCommand("python -c 'print(1)' | jq .", {
			isCommandAvailable: unavailableCommands("python", "jq"),
		}),
		["python3", "jq"],
	);
});

test("handles env prefixes and command wrappers", () => {
	assert.deepEqual(
		getMappedPackagesForCommand("env DEBUG=1 command python -c 'print(1)'", {
			isCommandAvailable: unavailableCommands("python"),
		}),
		["python3"],
	);
});

test("respects inline PATH assignments when checking command availability", () => {
	assert.deepEqual(
		getMappedPackagesForCommand("PATH=/custom/bin:$PATH python -c 'print(1)'", {
			env: { PATH: "/usr/bin" },
			isCommandAvailable(command, env) {
				assert.equal(command, "python");
				assert.equal(env.PATH, "/custom/bin:/usr/bin");
				return true;
			},
		}),
		[],
	);
});

test("does not rewrite nix shell commands", () => {
	assert.equal(
		rewriteCommandForNixShell("nix shell nixpkgs#python3 --command python -c 'print(1)'", {
			isCommandAvailable: unavailableCommands("python"),
		}),
		null,
	);
});

test("ignores comments and path-like executables", () => {
	assert.deepEqual(
		getMappedPackagesForCommand("./scripts/check.sh # python", {
			isCommandAvailable: unavailableCommands("python"),
		}),
		[],
	);
});

test("leaves commands alone when they already exist", () => {
	assert.equal(
		rewriteCommandForNixShell("python3 -c 'print(1)'", {
			isCommandAvailable: () => true,
		}),
		null,
	);
});

test("quotes commands safely for bash -lc", () => {
	assert.equal(
		quoteForBash("python -c \"print('hi')\""),
		"'python -c \"print('" + '"' + "'" + '"' + "'hi'" + '"' + "'" + '"' + "')\"'",
	);
});

test("rewrites a missing python command through nix shell", () => {
	assert.equal(
		rewriteCommandForNixShell("python -c \"print('pi-test')\"", {
			isCommandAvailable: unavailableCommands("python"),
		}),
		"nix shell nixpkgs#python3 --command bash -lc 'python -c \"print('" + '"' + "'" + '"' + "'pi-test'" + '"' + "'" + '"' + "')\"'",
	);
});
