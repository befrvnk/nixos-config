# pi-lsp improvement overview

## Goal

Make the pi LSP extension much more reliable for Kotlin and other slow-starting workspaces, especially when Gradle import or project indexing delays server readiness.

The main user-visible problem today is that the first semantic request can fail with a raw error like:

- `Timed out waiting for initialize from kotlin`

The extension already has a solid base, but it is still mostly **lazy** and treats startup as a binary success/failure event. Kotlin/Gradle projects need a more explicit lifecycle.

## Current state

The current implementation already does a few important things well:

- registers semantic tools in `index.ts`
- pools servers by `language:root` in `server.ts`
- exposes `/lsp-status` and `/lsp-restart`
- falls back gracefully for unsupported `workspace/symbol`
- detects project roots using language-specific markers in `paths.ts`

However, the current behavior still has gaps that explain the Kotlin timeout issue:

1. **Startup is lazy**
   - servers start on the first tool call via `ServerManager.get()`
   - `session_start` only updates footer text; it does not warm any server

2. **Readiness is too coarse**
   - `LspServer` tracks `started`, but not richer phases like initializing, indexing, ready, failed, or restarting
   - UI status only summarizes active server count, not whether a Kotlin server is still warming up

3. **First requests fail too bluntly**
   - tool handlers call `server.request(...)` directly after `get(...)`
   - if initialization stalls, the user gets a raw timeout instead of a structured “still warming up” result

4. **Kotlin root detection is not Gradle-optimized enough**
   - Kotlin root markers currently include `build.gradle(.kts)`
   - that can incorrectly anchor the server to a leaf module instead of the Gradle workspace root

5. **Cancellation is not wired through**
   - tool execute handlers ignore `_signal`
   - request/startup waiting cannot currently be cancelled cleanly

6. **Observability is limited**
   - stderr is ignored
   - there is no startup/import timing, failure classification, or restart count
   - no `/lsp-stop` or `/lsp-log`

7. **Fallback behavior is uneven**
   - `workspace/symbol` degrades nicely
   - other operations still tend to fail hard when the server is unavailable or warming up

## Recommended improvements

## 1. Warm Kotlin eagerly on `session_start`

**What to change**

Start or attach to likely LSP servers as soon as a session begins instead of waiting for the first tool call.

**Why**

This hides Kotlin/Gradle startup latency behind normal session startup and reduces the chance that the first hover/diagnostics request hits initialization timeout.

**How**

- use `pi.on("session_start", ...)` to detect likely workspace languages
- optionally also use `pi.on("resources_discover", ...)` if root detection should wait for project/resource discovery
- warm only the likely roots for the current workspace, not every configured language everywhere

**Implementation notes**

- `index.ts`: replace the current status-only `session_start` handler with a warmup flow
- `paths.ts`: reuse `detectLikelyWorkspaceLanguages()` and `detectProjectRoot()` to pick roots
- `server.ts`: add a `warm(language, root)` path that can start a server without needing a user request yet

## 2. Introduce an explicit readiness state machine

**What to change**

Track server lifecycle explicitly instead of a single `started` boolean.

**Suggested states**

- `idle`
- `starting`
- `initializing`
- `indexing`
- `ready`
- `failed`
- `restarting`
- `stopped`

**Why**

For Kotlin this is the difference between “server process exists” and “workspace is actually usable”.

**How**

Extend status data so each server runtime records:

- language
- workspace root
- pid
- current state
- startedAt / initializedAt / readyAt
- lastFailureReason
- restartCount
- recent request latency
- maybe last stderr snippet

**UI improvements**

Use `ctx.ui.setStatus()` for quick footer visibility:

- `Kotlin LSP: starting…`
- `Kotlin LSP: importing Gradle project…`
- `Kotlin LSP: ready`
- `Kotlin LSP: failed`

Optionally add `ctx.ui.setWidget()` for richer details when there is an active Kotlin runtime.

**Implementation notes**

- `types.ts`: expand `ServerStatus`
- `status.ts`: render richer details, including failures and readiness
- `server.ts`: emit state transitions during spawn, initialize, import/index, shutdown, and restart
- `index.ts`: update footer/widget whenever status changes

## 3. Improve first-call behavior

**What to change**

If a tool is called before Kotlin is ready, do not immediately fail with a raw initialize timeout.

**Preferred behavior**

1. wait briefly for readiness
2. if readiness arrives, continue the request normally
3. if it still is not ready, return a structured warmup response
4. optionally retry once after readiness completes

**Why**

This turns a mysterious failure into an understandable transient state.

**Example result**

- `Kotlin LSP is still starting for /repo`
- `State: indexing`
- `Elapsed: 18s`
- `Suggestion: retry shortly or run /lsp-status`

**Implementation notes**

- split startup timeout from request timeout
- add a `waitUntilReady({ signal, maxWaitMs })` helper
- classify warmup responses separately from hard failures
- preserve existing request methods once state becomes `ready`

## 4. Keep and expand control/debug commands

The extension already has:

- `/lsp-status`
- `/lsp-restart`

Those are a good start, but Kotlin support would benefit from more control.

**Add**

- `/lsp-stop` — stop all or selected runtimes without immediately restarting
- `/lsp-log` — show recent lifecycle events, stderr snippets, and last failures
- optional Kotlin aliases:
  - `/kotlin-lsp-status`
  - `/kotlin-lsp-restart`
  - `/kotlin-lsp-stop`

**Why**

These commands help when:

- Gradle import got stuck
- the user switched branches
- settings/build files changed
- a KMP or Android workspace layout changed

**Implementation notes**

- `index.ts`: add commands via `pi.registerCommand()`
- `server.ts`: keep recent event/log ring buffers per runtime

## 5. Tighten Kotlin workspace root detection

**What to change**

Use Gradle-workspace markers as the primary root selection strategy for Kotlin.

**Prefer markers like**

- `settings.gradle.kts`
- `settings.gradle`
- `gradlew`
- `.git`
- `pom.xml` for Maven projects

**Be careful with**

- `build.gradle.kts`
- `build.gradle`

These often identify a module, not the workspace root.

**Why**

One server per Gradle root is better than one server per leaf module:

- avoids duplicate servers
- improves cache reuse
- reduces re-import churn
- works better in Android/KMP monorepos

**Implementation notes**

- `constants.ts`: change Kotlin markers to prefer top-level workspace indicators
- `paths.ts`: consider “best root” selection instead of first-match selection
- preserve `.git` fallback for non-Gradle Kotlin repos

## 6. Treat Gradle-heavy projects as a separate startup path

**What to change**

Distinguish:

- process spawned
- LSP initialize completed
- workspace import/index complete
- semantic requests ready

**Why**

Kotlin failures often happen after the process exists but before the workspace is really usable.

**Helpful additions**

- detect import/indexing progress if the server exposes it
- surface import progress in status text/widget
- cache the last successful import per root
- record the last import failure reason
- detect build file changes and trigger restart/reimport

**Possible triggers for restart/reimport**

- `settings.gradle(.kts)`
- `build.gradle(.kts)`
- `gradle.properties`
- `gradle/libs.versions.toml`

## 7. Wire cancellation through startup and requests

**What to change**

Pass `ctx.signal` through any async waiting around LSP startup and requests.

**Why**

If the user aborts a turn, the extension should stop waiting for initialize/import and avoid orphan retries.

**Implementation notes**

- `index.ts`: stop ignoring the tool `signal` parameter
- add abort-aware wrappers around:
  - warmup waits
  - request waits
  - retry timers
- if the protocol/server supports request cancellation, forward cancellation downstream too

## 8. Return clearer, actionable errors

**What to change**

Replace generic failures with classified errors.

**Useful categories**

- server not installed
- failed to spawn process
- initialize timed out
- workspace import failed
- request timed out after ready
- file outside workspace root
- unsupported method
- workspace not recognized as a project

**Why**

A structured error is much easier to act on than “Timed out waiting for initialize from kotlin”.

**Implementation notes**

Add a small error taxonomy in `server.ts` and render it consistently in tool results and `/lsp-log` output.

## 9. Add graceful fallback behavior beyond `workspace_symbols`

**What to change**

If Kotlin LSP is unavailable, return a helpful degraded response instead of a dead end.

**Examples**

- `diagnostics`: suggest a build/compile fallback when LSP is down
- `definition` / `references`: say LSP is unavailable and suggest `grep` or `workspace_symbols` when possible
- `document_symbols`: fall back to plain file reading if semantic parsing is unavailable

**Why**

This keeps the agent productive even during partial outages.

## 10. Track startup and request metrics

**What to change**

Collect lightweight runtime metrics.

**Track at least**

- startup duration
- initialize duration
- import duration
- request latency by method
- restart count
- last failure reason
- maybe time since last successful request

**Why**

This helps tune timeouts and identify whether delays come from spawn, initialize, or Gradle import.

## 11. Consider dynamic tool activation

**What to change**

Use `pi.setActiveTools()` to hide or gate tools when the extension is unhealthy.

**Possible policy**

- keep tools active while healthy or warming
- if Kotlin repeatedly fails to start, either:
  - keep tools active but return degraded responses, or
  - temporarily disable only Kotlin-dependent tools until restart

**Why**

This avoids the model repeatedly calling tools that are guaranteed to fail.

## 12. Make restart and reload ergonomic

**What to change**

Support both server restart and full extension reload.

**Add**

- `/lsp-restart`
- optional per-language restart
- `/reload-runtime` or equivalent when extension code changes need a clean reset

**Why**

Recovery should be a one-command path.

## Highest-ROI implementation plan

If we want the biggest reliability improvement with the least code churn, do these first:

### Phase 1 — immediate UX and reliability wins

1. **Warm likely Kotlin roots on `session_start`**
2. **Add explicit readiness states and surface them in footer status**
3. **Upgrade first-call behavior to return “still warming up” instead of raw initialize timeout**
4. **Expand `/lsp-status` and `/lsp-restart`; add `/lsp-stop`**

### Phase 2 — Kotlin/Gradle correctness

5. **Fix Kotlin root detection to prefer Gradle workspace roots**
6. **Distinguish initialize vs import/index readiness**
7. **Restart/reimport when Gradle files change**

### Phase 3 — operability and polish

8. **Add cancellation plumbing**
9. **Add structured error taxonomy**
10. **Add logging/metrics and `/lsp-log`**
11. **Expand fallback behavior**
12. **Consider dynamic tool activation**

## Proposed code-shape changes

## `index.ts`

- warm likely servers during `session_start`
- possibly also react to `resources_discover`
- stop ignoring tool cancellation signal
- wrap tool calls in “wait briefly, then warming response” logic
- add `/lsp-stop` and `/lsp-log`

## `server.ts`

- split spawn, initialize, import/index, ready, failed states
- add `warm()`, `waitUntilReady()`, `restart()`, and log/metrics helpers
- capture stderr snippets instead of discarding them
- classify failures
- make request waiting abort-aware

## `paths.ts` and `constants.ts`

- improve Kotlin root heuristics for Gradle/Maven repos
- prefer workspace-root markers over leaf-module markers

## `types.ts`

- enrich `ServerStatus`
- add error category and metrics types

## `status.ts`

- render readiness, failures, and metrics in `/lsp-status`
- optionally support a richer widget view

## Testing priorities

Add mocked tests for the new lifecycle, especially:

- warmup triggered on `session_start`
- state transitions: starting → initializing → indexing → ready
- initialize timeout produces a structured warmup/failure response
- cancellation aborts pending startup waits
- Kotlin root detection prefers `settings.gradle(.kts)` or `gradlew` over leaf `build.gradle(.kts)`
- restart after build-file change
- `/lsp-log` and metrics rendering

## Bottom line

The current extension is already close in a few areas: it has server pooling, status/restart commands, and some graceful degradation. The missing piece is a **real server lifecycle model**, especially for Kotlin.

The most important shift is:

- from **lazy binary startup**
- to **eager warmup + explicit readiness + structured degraded behavior**

That should eliminate most “timed out waiting for initialize from kotlin” failures and make the remaining failures much easier to understand and recover from.
