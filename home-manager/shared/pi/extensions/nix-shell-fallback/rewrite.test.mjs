import test from "node:test";
import assert from "node:assert/strict";
import {
	getMappedPackagesForCommand,
	isUnavailableDarwinDeveloperToolShim,
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

test("treats background jobs as command separators", () => {
	assert.deepEqual(
		getMappedPackagesForCommand("python -c 'print(1)' & jq .", {
			isCommandAvailable: unavailableCommands("python", "jq"),
		}),
		["python3", "jq"],
	);
});

test("collects packages for xargs subcommands", () => {
	assert.deepEqual(
		getMappedPackagesForCommand("fd -0 | xargs -0 rg foo", {
			isCommandAvailable: unavailableCommands("fd", "rg"),
		}),
		["fd", "ripgrep"],
	);
});

test("collects packages for find -exec subcommands", () => {
	assert.deepEqual(
		getMappedPackagesForCommand("find . -name '*.ts' -exec rg foo {} \\;", {
			isCommandAvailable: unavailableCommands("rg"),
		}),
		["ripgrep"],
	);
});

test("collects packages inside nested shell command strings", () => {
	assert.deepEqual(
		getMappedPackagesForCommand("bash -lc 'python -c \"print(1)\" | jq .'", {
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

test("treats unavailable macOS developer tool shims as missing", () => {
	assert.equal(
		isUnavailableDarwinDeveloperToolShim("python3", "/usr/bin/python3", {
			platform: "darwin",
			runXcrunFind: () => false,
		}),
		true,
	);
	assert.equal(
		isUnavailableDarwinDeveloperToolShim("python3", "/nix/store/python3/bin/python3", {
			platform: "darwin",
			runXcrunFind: () => false,
		}),
		false,
	);
	assert.equal(
		isUnavailableDarwinDeveloperToolShim("python3", "/usr/bin/python3", {
			platform: "linux",
			runXcrunFind: () => false,
		}),
		false,
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
