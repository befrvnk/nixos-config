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

test("blockIfSuspiciousBashCommand allows one read-only inspection command", () => {
  assert.equal(blockIfSuspiciousBashCommand("git status", cwd), undefined);
  assert.equal(blockIfSuspiciousBashCommand("git diff", cwd), undefined);
  assert.equal(blockIfSuspiciousBashCommand("rg TODO src", cwd), undefined);
  assert.equal(blockIfSuspiciousBashCommand("find ./src -name '*.ts'", cwd), undefined);
  assert.equal(blockIfSuspiciousBashCommand("sed -n '1,20p' file.ts", cwd), undefined);
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
  assert.match(blockIfSuspiciousBashCommand("cat file > out.txt", cwd) ?? "", /one simple inspection command/);
  assert.match(blockIfSuspiciousBashCommand("cat $(pwd)", cwd) ?? "", /one simple inspection command/);
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

test("blockIfSuspiciousBashCommand rejects shell composition and expansion", () => {
  for (const command of [
    "cat x & pwd",
    "git status && rg TODO",
    "ls | head",
    "ls; pwd",
    "ls\npwd",
    "PAGER=less git log",
    "cat $HOME/file",
    "cat *.ts",
  ]) {
    assert.match(blockIfSuspiciousBashCommand(command, cwd) ?? "", /one simple inspection command|environment assignments/, command);
  }
});

test("blockIfSuspiciousBashCommand blocks input redirection", () => {
  assert.match(
    blockIfSuspiciousBashCommand("cat < /etc/passwd", cwd) ?? "",
    /one simple inspection command/,
  );
  assert.equal(blockIfSuspiciousBashCommand("grep '<div>' page.html", cwd), undefined);
});

test("blockIfSuspiciousBashCommand blocks write and execution options", () => {
  for (const command of [
    "fd -x touch {}",
    "fd -X echo",
    "rg --pre cat pattern",
    "sed --in-place file.txt",
    "sed -I.bak file.txt",
    "sort -o output.txt input.txt",
    "sort --compress-program=gzip input.txt",
    "tree -o output.txt",
    "file -C",
  ]) {
    assert.notEqual(blockIfSuspiciousBashCommand(command, cwd), undefined, command);
  }

  assert.match(
    blockIfSuspiciousBashCommand("find . -exec rm {} ;", cwd) ?? "",
    /one simple inspection command/,
  );
  assert.match(blockIfSuspiciousBashCommand("find . -delete", cwd) ?? "", /find actions/);
  assert.equal(blockIfSuspiciousBashCommand("find ./src -name '*.ts'", cwd), undefined);
});

test("blockIfSuspiciousBashCommand restricts mutation-capable git forms", () => {
  for (const command of [
    "git branch new-branch",
    "git branch -D old",
    "git tag release",
    "git remote add origin example",
    "git remote set-url origin example",
    "git -c core.pager=less log",
    "git -C /tmp status",
    "git --git-dir=/tmp/repo status",
    "git diff --output=result.diff",
    "git diff --ext-diff",
    "git show --textconv",
    "git cat-file --filters HEAD:file",
  ]) {
    assert.notEqual(blockIfSuspiciousBashCommand(command, cwd), undefined, command);
  }

  assert.equal(blockIfSuspiciousBashCommand("git branch --list", cwd), undefined);
  assert.equal(blockIfSuspiciousBashCommand("git tag --list", cwd), undefined);
  assert.equal(blockIfSuspiciousBashCommand("git remote -v", cwd), undefined);
});

test("blockIfSuspiciousPath blocks sensitive system paths with boundary matching", () => {
  assert.match(
    blockIfSuspiciousPath("read", { path: "/etc/passwd" }, cwd) ?? "",
    /blocked runtime or system path/,
  );
  assert.match(
    blockIfSuspiciousPath("read", { path: "/root/.ssh/id_rsa" }, cwd) ?? "",
    /blocked runtime or system path/,
  );
  assert.equal(blockIfSuspiciousPath("read", { path: "/etcd/data.json" }, cwd), undefined);
});
