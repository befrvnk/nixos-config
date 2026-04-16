import test from "node:test";
import assert from "node:assert/strict";
import {
  blockIfSuspiciousBashCommand,
  blockIfSuspiciousPath,
  containsUnquotedCharacter,
  containsUnquotedCommandSubstitution,
} from "./guard-utils.ts";

const cwd = "/repo/project";

test("blockIfSuspiciousPath rejects runtime paths but allows /dev/null", () => {
  assert.match(
    blockIfSuspiciousPath("read", { path: "/proc/cpuinfo" }, cwd) ?? "",
    /blocked runtime or system path/,
  );
  assert.equal(blockIfSuspiciousPath("read", { path: "/dev/null" }, cwd), undefined);
  assert.equal(blockIfSuspiciousPath("read", { path: "./src/index.ts" }, cwd), undefined);
});

test("quoted characters and substitutions are ignored, unquoted ones are blocked", () => {
  assert.equal(containsUnquotedCharacter("printf '>'", ">"), false);
  assert.equal(containsUnquotedCharacter("echo hi > out.txt", ">"), true);
  assert.equal(containsUnquotedCommandSubstitution("echo '`pwd`'"), false);
  assert.equal(containsUnquotedCommandSubstitution("echo $(pwd)"), true);
});

test("blockIfSuspiciousBashCommand allows read-only inspection commands", () => {
  assert.equal(blockIfSuspiciousBashCommand("git status && rg TODO src", cwd), undefined);
  assert.equal(blockIfSuspiciousBashCommand("env DEBUG=1 find ./src -name '*.ts'", cwd), undefined);
});

test("blockIfSuspiciousBashCommand blocks destructive commands and risky syntax", () => {
  assert.match(blockIfSuspiciousBashCommand("rm -rf tmp", cwd) ?? "", /Blocked command: rm/);
  assert.match(
    blockIfSuspiciousBashCommand("git commit -m test", cwd) ?? "",
    /Blocked subcommand: git commit/,
  );
  assert.match(
    blockIfSuspiciousBashCommand("sed -i 's/x/y/' file.txt", cwd) ?? "",
    /in-place sed edits/,
  );
  assert.match(blockIfSuspiciousBashCommand("echo hi > out.txt", cwd) ?? "", /output redirection/);
  assert.match(blockIfSuspiciousBashCommand("echo $(pwd)", cwd) ?? "", /command substitution/);
  assert.match(
    blockIfSuspiciousBashCommand("cat /proc/cpuinfo", cwd) ?? "",
    /blocked runtime or system paths/,
  );
  assert.match(
    blockIfSuspiciousBashCommand("cat @/proc/cpuinfo", cwd) ?? "",
    /blocked runtime or system paths/,
  );
  assert.match(
    blockIfSuspiciousBashCommand("head @../../proc/cpuinfo", cwd) ?? "",
    /blocked runtime or system paths/,
  );
});
