# Pi Extension Unit Test Plan

## Goal

Add fast unit tests for every existing pi extension in this repo so regressions are caught before a rebuild or manual interactive verification.

## Scope

Existing extensions:

1. `nix-shell-fallback`
2. `pi-lsp`
3. `subagents`
4. `system-theme-sync`

The focus is **pure logic and small deterministic helpers**. We intentionally avoid interactive TUI and live pi runtime tests in this phase.

## Test Strategy

### 1. nix-shell-fallback

**Primary risk:** shell command parsing and package rewrite mistakes.

**Unit-test targets**
- command tokenization and prefix handling
- package mapping for missing tools
- nix-shell rewrite generation
- quoting edge cases
- ignoring comments and path-like executables

**Implementation status**
- Existing `rewrite.test.mjs` kept
- Expanded with another parser edge case

### 2. pi-lsp

**Primary risk:** path resolution, root detection, LSP output formatting, JSON-RPC framing.

**Unit-test targets**
- `paths.ts`
  - `stripAtPrefix`
  - `resolveFilePath`
  - `detectLanguage`
  - `detectProjectRoot`
  - `toZeroIndexedPosition`
  - `ensureActionSupportsPath`
- `formatting.ts`
  - hover rendering
  - location/document/workspace symbol formatting
  - diagnostics formatting
- `server.ts`
  - JSON-RPC stream parser buffering and malformed payload handling

**Future phase**
- mocked `ServerManager` lifecycle tests
- config loading failure cases via isolated module reloads

### 3. system-theme-sync

**Primary risk:** theme detection parsing and bad UI state application.

**Unit-test targets**
- `parseLinuxTheme`
- `applyTheme`

**Future phase**
- polling lifecycle smoke tests with mocked timers
- platform-specific detector tests via command stubs

### 4. subagents

**Primary risk:** unsafe command filtering, result parsing, markdown formatting, command parsing, and model gating.

**Unit-test targets**
- `model-policy.ts`
  - allowed model validation
  - reviewer config sanity
- `progress.ts`
  - progress block parsing/extraction/stripping
- `formatting.ts`
  - markdown section splitting
  - bullet parsing
  - ID shortening
  - run/history rendering
- `guard-utils.ts`
  - suspicious path checks
  - shell segmentation and command blocking
- `commands.ts`
  - review command parsing
  - quoted argument tokenization
  - subagent task lookup behavior
- `workflows/explore/results.ts`
  - structured output parsing
  - final result rendering
- `workflows/review/index.ts`
  - review prompt construction
  - structured output parsing
  - final result rendering

**Future phase**
- mocked git diff collection tests
- mocked `runSingleTask()` event-stream helper tests

## Execution

Run all tests with:

```bash
./scripts/test-pi-extensions.sh
```

This uses `nix shell nixpkgs#tsx` so no permanent Node package installation is required.

## Phasing

### Phase 1
- Add pure unit tests across all extensions
- Extract small helper modules where needed to make logic importable

### Phase 2
- Add mocked boundary tests for git/LSP/process interactions

### Phase 3
- Add optional runtime smoke tests for extension registration flows if needed
