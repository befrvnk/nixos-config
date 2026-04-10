import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  formatDiagnostics,
  formatDocumentSymbols,
  formatLocationUri,
  formatLocations,
  formatRange,
  formatWorkspaceSymbols,
  hoverToText,
  previewAtLocation,
  renderMarkup,
} from "./formatting.ts";

test("formatRange and formatLocationUri render human readable locations", () => {
  assert.equal(
    formatRange({
      start: { line: 1, character: 2 },
      end: { line: 3, character: 4 },
    }),
    "2:3-4:5",
  );

  const uri = pathToFileURL(path.join(os.homedir(), "project", "file.ts")).href;
  assert.equal(formatLocationUri(uri), "~/project/file.ts");
});

test("previewAtLocation returns the relevant source line", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-format-"));
  const file = path.join(dir, "sample.ts");
  fs.writeFileSync(file, "const a = 1;\nconst b = 2;\n");

  assert.equal(
    previewAtLocation(pathToFileURL(file).href, {
      start: { line: 1, character: 0 },
      end: { line: 1, character: 5 },
    }),
    "const b = 2;",
  );
});

test("renderMarkup and hoverToText support strings, arrays, and markup objects", () => {
  assert.equal(renderMarkup("plain text"), "plain text");
  assert.equal(
    renderMarkup([{ value: "first" }, "second"]),
    "first\n\nsecond",
  );
  assert.equal(hoverToText({ contents: { kind: "markdown", value: "**bold**" } }), "**bold**");
  assert.equal(hoverToText({}), "No hover information available.");
});

test("formatLocations includes previews and truncation counts", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-locations-"));
  const file = path.join(dir, "sample.ts");
  fs.writeFileSync(file, "alpha\nbeta\ngamma\n");
  const uri = pathToFileURL(file).href;

  const text = formatLocations(
    "Definitions",
    [
      {
        uri,
        range: {
          start: { line: 1, character: 0 },
          end: { line: 1, character: 4 },
        },
      },
      {
        uri,
        range: {
          start: { line: 2, character: 0 },
          end: { line: 2, character: 5 },
        },
      },
    ],
    1,
  );

  assert.match(text, /^Definitions:/);
  assert.match(text, /1\. .*beta/);
  assert.match(text, /… 1 more result\(s\)/);
});

test("formatDocumentSymbols flattens nested symbols", () => {
  const uri = pathToFileURL(path.join(os.tmpdir(), "doc.ts")).href;
  const text = formatDocumentSymbols(
    [
      {
        name: "Root",
        kind: 5,
        selectionRange: {
          start: { line: 0, character: 0 },
          end: { line: 0, character: 4 },
        },
        children: [
          {
            name: "child",
            kind: 6,
            selectionRange: {
              start: { line: 1, character: 2 },
              end: { line: 1, character: 7 },
            },
          },
        ],
      },
    ],
    uri,
    10,
  );

  assert.match(text, /\[Class\] Root/);
  assert.match(text, /\[Method\] Root\.child/);
});

test("formatWorkspaceSymbols and formatDiagnostics render optional metadata", () => {
  const workspace = formatWorkspaceSymbols(
    [
      {
        name: "searchMe",
        kind: 12,
        containerName: "MyModule",
        location: {
          uri: pathToFileURL("/tmp/workspace.ts").href,
          range: {
            start: { line: 0, character: 0 },
            end: { line: 0, character: 8 },
          },
        },
      },
    ],
    10,
  );
  assert.match(workspace, /\[Function\] searchMe \(MyModule\)/);

  const diagnostics = formatDiagnostics(
    [
      {
        severity: 1,
        code: "TS1005",
        source: "tsserver",
        message: "Missing semicolon",
        range: {
          start: { line: 4, character: 1 },
          end: { line: 4, character: 2 },
        },
      },
    ],
    "src/example.ts",
    10,
  );
  assert.match(diagnostics, /Error \[TS1005\]/);
  assert.match(diagnostics, /\(tsserver\) — Missing semicolon/);
});
