# pi-lsp implementation plan

## Implementation handoff summary

Use this summary first if you are implementing in a fresh session.

### What we are solving

Kotlin and Gradle-heavy workspaces can take long enough to initialize that the first semantic request fails with:

- `Timed out waiting for initialize from kotlin`

The current extension already pools servers and exposes basic status/restart commands, but it still behaves like a mostly lazy on-demand wrapper around JSON-RPC requests.

### Highest-value changes

If implementation time is limited, do these first:

1. warm likely Kotlin roots on `session_start`
2. add explicit runtime states and surface them in `/lsp-status` + footer status
3. replace raw initialize timeout with a structured “still warming up” result
4. improve Kotlin root detection to prefer Gradle workspace roots
5. add `/lsp-stop` and richer restart/status output

### Minimum acceptable first landing

A good first landing should deliver all of the following:

- likely Kotlin roots warm eagerly on session start
- server status distinguishes `starting`, `initializing`, `ready`, and `failed`
- first semantic requests no longer fail with a bare initialize timeout
- `/lsp-status` shows readiness and last failure
- Kotlin root detection prefers `settings.gradle(.kts)` or `gradlew` over leaf `build.gradle(.kts)`

## Goal

Make `pi-lsp` reliable and debuggable for Kotlin, while improving the shared LSP lifecycle for all supported languages.

Desired outcome:

- the extension starts likely LSP servers before the first request
- the user and agent can see whether a server is warming up, ready, or failed
- tool calls degrade gracefully while startup is still in progress
- Kotlin servers are keyed to the correct Gradle workspace root
- restart/stop/debug flows are explicit and easy to use

## Non-goals for this round

These can come later if needed:

- file watchers for automatic restart on every workspace file change
- disabling/enabling tools dynamically via `pi.setActiveTools()`
- full persistent metrics storage across sessions
- deep Kotlin-specific integration beyond generic LSP lifecycle improvements

## Current repo state

The current extension already provides:

- tool registration in `index.ts`
- server pooling by `language:root` in `server.ts`
- root detection in `paths.ts`
- `/lsp-status` and `/lsp-restart`
- tests for JSON-RPC framing, lifecycle basics, formatting, and path resolution

Current gaps that matter for implementation:

- `session_start` only updates the footer
- `LspServer` has a `started` boolean, not a richer lifecycle model
- tool execute handlers ignore the tool abort signal
- server stderr is discarded
- Kotlin root markers include `build.gradle(.kts)`, which can pick leaf modules
- failures are mostly plain `Error`s with generic messages

## Target architecture

## Runtime model

Introduce a runtime record for each `language:root` server with:

- lifecycle state
- timestamps for spawn / initialize / ready / last failure
- recent stderr and lifecycle events
- request latency metrics
- restart count

### Suggested state enum

- `starting`
- `initializing`
- `indexing`
- `ready`
- `failed`
- `stopped`
- `restarting`

Notes:
- TypeScript and Nix may often move directly from `initializing` to `ready`
- Kotlin may spend meaningful time in `indexing`
- if the Kotlin server exposes no explicit indexing signal yet, we can still model `indexing` heuristically after `initialize` and before the first successful semantic request

## Error taxonomy

Add explicit failure categories so tool wrappers can present actionable results.

### Suggested categories

- `not_configured`
- `spawn_failed`
- `initialize_timeout`
- `initialize_failed`
- `workspace_import_failed`
- `request_timeout`
- `unsupported_method`
- `no_project`
- `outside_workspace`
- `aborted`

## Status surface

### Footer

Use `ctx.ui.setStatus("pi-lsp", ...)` to show a compact high-signal summary, for example:

- `LSP: kotlin starting…`
- `LSP: kotlin indexing…`
- `LSP: kotlin ready`
- `LSP: kotlin failed`

### Command output

`/lsp-status` should show:

- configured languages
- active runtimes
- root
- pid
- state
- uptime
- restart count
- last failure reason
- last initialize / ready duration if known

### Optional widget

Defer unless needed. A widget is useful if footer status becomes too compressed, but it should not block the first implementation.

# Phased implementation plan

## Phase 0 — prep and type scaffolding

### Objective

Create the types and internal interfaces needed for the later phases without changing external behavior too much.

### Changes

#### `home-manager/shared/pi/extensions/pi-lsp/types.ts`

Add types for:

- `ServerLifecycleState`
- `LspFailureCategory`
- `LspFailureInfo`
- `RequestMetric`
- richer `ServerStatus`

Suggested `ServerStatus` expansion:

- `language`
- `root`
- `pid?`
- `state`
- `startedAt?`
- `initializedAt?`
- `readyAt?`
- `failedAt?`
- `openDocuments`
- `restartCount`
- `lastFailure?`
- `lastStderrLines?`
- `lastRequest?`

#### `home-manager/shared/pi/extensions/pi-lsp/server.ts`

Introduce internal helpers for:

- lifecycle transition updates
- failure classification
- simple ring buffers for logs / stderr / recent requests

### Tests

- add pure tests for any new classifiers/helpers

### Acceptance criteria

- no behavior change required yet
- types compile cleanly
- helper logic is covered by unit tests where practical

## Phase 1 — lifecycle state machine in `server.ts`

### Objective

Replace the current binary startup model with an explicit runtime lifecycle.

### Changes

#### `home-manager/shared/pi/extensions/pi-lsp/server.ts`

Refactor `LspServer` so it:

- tracks a lifecycle state instead of only `started`
- records timestamps for key milestones
- captures recent stderr lines instead of discarding stderr entirely
- records last failure and failure category
- tracks restart count
- tracks basic request latency by method

Add APIs roughly like:

- `start()`
- `stop()`
- `restart()`
- `warm()`
- `waitUntilReady({ signal, maxWaitMs })`
- `getStatus()`
- `getRecentLogLines()`

State transitions should look like:

- new runtime → `starting`
- process spawned → `initializing`
- initialize complete → `indexing` or `ready`
- first semantic success / explicit progress completion → `ready`
- failure at any point → `failed`
- restart command → `restarting` then `starting`
- stop command → `stopped`

#### `ServerManager`

Expand the manager so it:

- can warm a runtime without immediately issuing a tool request
- can return status for both active and starting runtimes
- can stop one or all runtimes
- can restart one or all runtimes
- can surface logs for a selected runtime or all runtimes

### Tests

Add mocked lifecycle tests for:

- start transitions to `ready`
- initialize timeout transitions to `failed` with `initialize_timeout`
- restart increments `restartCount`
- stderr lines are retained in a bounded buffer

### Acceptance criteria

- `getStatus()` exposes meaningful lifecycle state
- failures are classified, not just plain strings
- server stderr is no longer silently lost

## Phase 2 — eager warmup on session start

### Objective

Hide Kotlin startup latency by warming likely workspaces early.

### Changes

#### `home-manager/shared/pi/extensions/pi-lsp/index.ts`

Replace the current `session_start` behavior with warmup logic:

- determine likely languages from `ctx.cwd`
- determine the best root per language
- call `manager.warm(language, root)` in the background
- keep UI status updated before, during, and after warmup

Potential event hooks:

- `session_start` for eager warmup
- optionally `resources_discover` if later testing shows repo/resource discovery materially improves root selection

Important behavior:

- warm only likely languages for the current workspace
- do not block session start on warmup completion
- warmup failures should update status but not crash the extension

### Tests

Add tests for:

- likely Kotlin workspace triggers a warm request on `session_start`
- a workspace with no matching language markers does not start unnecessary runtimes
- warmup failure leaves the runtime in `failed` and updates status output

### Acceptance criteria

- Kotlin server startup begins before the first hover/diagnostics request
- session startup remains responsive
- status reflects warming progress

## Phase 3 — better first-call behavior and cancellation

### Objective

Turn cold-start failures into structured transient results and make waiting abort-aware.

### Changes

#### `home-manager/shared/pi/extensions/pi-lsp/index.ts`

Refactor tool execution flow so wrappers:

1. resolve language and root
2. obtain or warm the runtime
3. wait briefly for readiness using the tool abort signal
4. continue normally if ready
5. if still warming, return a structured result instead of throwing a raw initialize timeout

Introduce a helper around all semantic actions, for example:

- `getReadyServerOrWarmupResult(...)`

Structured warmup result should include:

- language
- root
- current state
- elapsed warmup time
- last known failure if any
- retry suggestion

#### `home-manager/shared/pi/extensions/pi-lsp/server.ts`

Add abort-aware waiting:

- `waitUntilReady({ signal, maxWaitMs })`
- utility to race timeout and `AbortSignal`
- optional request cancellation support if the server/protocol path is practical

#### Error behavior

Differentiate:

- warmup still in progress
- hard initialize failure
- request timeout after ready
- aborted by user

### Tests

Add tests for:

- cold request waits briefly and then returns a warmup result
- request proceeds once readiness is reached inside the wait window
- aborted request exits quickly with category `aborted`
- request timeout after ready is reported differently from initialize timeout

### Acceptance criteria

- bare `Timed out waiting for initialize from kotlin` is no longer the normal first-call UX
- tool wrappers use the provided abort signal
- warmup results are structured and actionable

## Phase 4 — Kotlin root detection correctness

### Objective

Ensure Kotlin server pooling happens at the real workspace root, not random leaf modules.

### Changes

#### `home-manager/shared/pi/extensions/pi-lsp/constants.ts`

Adjust Kotlin root markers so primary workspace markers come first:

Preferred high-confidence markers:

- `settings.gradle.kts`
- `settings.gradle`
- `gradlew`
- `pom.xml`
- `.git`

Do not treat `build.gradle(.kts)` as an immediate root winner in the same way. If retained at all, use them as a lower-confidence fallback.

#### `home-manager/shared/pi/extensions/pi-lsp/paths.ts`

Refactor `detectProjectRoot()` to use a “best root” strategy rather than first marker hit.

Suggested Kotlin behavior:

1. walk upward gathering matching directories
2. prefer the highest directory containing `settings.gradle(.kts)` or `gradlew`
3. otherwise prefer Maven root markers
4. otherwise fall back to `.git`
5. use leaf `build.gradle(.kts)` only as a last fallback if nothing better exists

### Tests

Expand `paths.test.ts` with cases covering:

- multi-module Gradle repo
- nested Android/KMP-style modules
- standalone Kotlin module with only `build.gradle.kts`
- Maven Kotlin project
- file outside any recognized project falling back to `.git` or start dir

### Acceptance criteria

- a Kotlin file inside a multi-module Gradle repo resolves to the top-level workspace root
- duplicate per-module server creation is reduced or eliminated for common Gradle layouts

## Phase 5 — status, control commands, and logs

### Objective

Make the extension debuggable without reading code or restarting the whole pi session.

### Changes

#### `home-manager/shared/pi/extensions/pi-lsp/status.ts`

Expand formatting to show:

- runtime state
n- root
- pid
- uptime
- restart count
- last failure category/message/time
- initialize and ready durations where known
- maybe last request method/latency

#### `home-manager/shared/pi/extensions/pi-lsp/index.ts`

Add commands:

- `/lsp-stop` — stop all running runtimes
- `/lsp-log` — show recent lifecycle and stderr lines

Keep existing:

- `/lsp-status`
- `/lsp-restart`

Optional aliases only if they add real value:

- `/kotlin-lsp-status`
- `/kotlin-lsp-restart`
- `/kotlin-lsp-stop`

### Tests

Add tests for status formatting and log rendering.

### Acceptance criteria

- user can inspect readiness/failure without guessing
- user can stop or restart runtimes explicitly
- recent stderr and lifecycle events are visible via command output

## Phase 6 — Gradle-aware readiness and restart triggers

### Objective

Improve Kotlin behavior after initialize completes but before the workspace is truly usable.

### Changes

#### `home-manager/shared/pi/extensions/pi-lsp/server.ts`

Add a Kotlin-oriented readiness policy:

- after `initialize`, stay in `indexing` until the runtime appears semantically usable
- if the server exposes progress notifications, use them
- otherwise use a heuristic such as “first successful semantic request marks ready”

#### `home-manager/shared/pi/extensions/pi-lsp/index.ts` or helper module

Add lightweight change detection for relevant Gradle files when a tool call happens:

- if root build metadata changed since last successful ready/import state, mark runtime stale and restart before serving the next Kotlin request

Relevant files:

- `settings.gradle`
- `settings.gradle.kts`
- `build.gradle`
- `build.gradle.kts`
- `gradle.properties`
- `gradle/libs.versions.toml`

Important note:

Do this lazily on request first. Avoid adding a filesystem watcher unless it is clearly needed.

### Tests

Add tests for:

- initialize complete but runtime still reported as `indexing`
- first successful semantic request promotes runtime to `ready`
- changed build metadata causes restart on next request

### Acceptance criteria

- Kotlin status no longer overclaims readiness immediately after initialize
- common Gradle changes recover via explicit or lazy restart behavior

## Phase 7 — graceful fallbacks and polish

### Objective

Keep the extension useful when LSP is degraded or unavailable.

### Changes

#### `home-manager/shared/pi/extensions/pi-lsp/index.ts`

Improve user-facing tool results when the runtime is unavailable:

- `workspace_symbols`: keep current graceful degradation
- `definition` / `references`: mention LSP unavailable and suggest `grep` if appropriate
- `diagnostics`: say diagnostics unavailable and suggest project build/compile verification
- `document_symbols`: say semantic parsing unavailable; suggest reading file or retrying after warmup

Avoid pretending that fallback is equivalent to semantic LSP support.

### Tests

- add coverage for fallback result formatting

### Acceptance criteria

- failures guide the user or model toward the next best step
- extension no longer feels like a dead end when Kotlin LSP is unhealthy

# File-by-file change map

## `home-manager/shared/pi/extensions/pi-lsp/index.ts`

Primary work:

- eager warmup on `session_start`
- maybe `resources_discover` hook later
- shared helper for readiness wait + structured warmup result
- use tool `signal` instead of ignoring `_signal`
- richer footer status updates
- add `/lsp-stop` and `/lsp-log`

## `home-manager/shared/pi/extensions/pi-lsp/server.ts`

Primary work:

- lifecycle state machine
- log/stderr retention
- failure classification
- restart and stop helpers
- readiness wait helper
- metrics collection
- manager support for warm/status/log/restart/stop

## `home-manager/shared/pi/extensions/pi-lsp/paths.ts`

Primary work:

- smarter Kotlin root detection
- maybe split generic root detection from Kotlin-specific prioritization

## `home-manager/shared/pi/extensions/pi-lsp/constants.ts`

Primary work:

- reprioritize Kotlin root markers

## `home-manager/shared/pi/extensions/pi-lsp/status.ts`

Primary work:

- richer status formatting
- maybe separate “compact footer summary” and “full command summary” helpers

## `home-manager/shared/pi/extensions/pi-lsp/types.ts`

Primary work:

- lifecycle, failure, metric, and expanded status types

## `home-manager/shared/pi/extensions/pi-lsp/*.test.ts`

Expected new or expanded coverage:

- `paths.test.ts`
- `server.test.ts`
- `server-lifecycle.test.ts`
- maybe a new `status.test.ts`
- maybe a new `index.test.ts` if registration/wrapper logic gets extracted enough to unit test cleanly

# Recommended PR slices

## PR 1 — lifecycle and status foundations

Include:

- Phase 0
- Phase 1
- status formatting updates
- tests for lifecycle and stderr retention

Do not include warmup yet.

## PR 2 — eager warmup and first-call UX

Include:

- Phase 2
- Phase 3
- structured warmup results
- cancellation plumbing

## PR 3 — Kotlin root detection and Gradle heuristics

Include:

- Phase 4
- initial part of Phase 6
- path tests for multi-module repos

## PR 4 — operator controls and fallback polish

Include:

- Phase 5
- Phase 7
- `/lsp-stop`
- `/lsp-log`
- fallback response improvements

## Optional PR 5 — deeper Kotlin indexing support

Include only if needed after testing with real projects:

- explicit indexing/progress integration
- lazy restart on build metadata changes
- more nuanced ready/import semantics

# Verification checklist

After implementation, verify against a real Kotlin/Gradle repo:

1. start pi in the repo
2. confirm footer/status shows Kotlin warmup automatically
3. run `/lsp-status` before any manual LSP request
4. issue a first `hover` or `diagnostics` request during warmup
5. confirm result is structured and not a raw initialize timeout
6. wait for ready state and retry
7. confirm request succeeds
8. touch a Gradle file and confirm restart/reimport behavior is understandable
9. run `/lsp-log` and confirm recent stderr/lifecycle details are visible
10. run `/lsp-stop` then issue another semantic request and confirm warmup recovers cleanly

# Open questions to answer during implementation

1. Does the configured Kotlin server emit usable progress notifications for import/indexing?
   - if yes, hook them into `indexing`
   - if no, use the heuristic ready model first

2. Should `/lsp-status` show starting runtimes even before they are ready?
   - recommended answer: yes

3. Should warmup results be returned as normal success content or as tool errors?
   - recommended answer: normal success content with structured details, because warmup is transient and actionable

4. Should Kotlin-specific commands be added now?
   - recommended answer: probably no at first; start with generic `/lsp-*` commands unless user feedback demands language-specific aliases

# Bottom line

Implement this in four practical slices:

1. lifecycle state + richer status
2. eager warmup + first-call UX + cancellation
3. Kotlin root correctness + Gradle-aware readiness
4. control/debug commands + fallback polish

That sequence keeps the work incremental, testable, and likely to eliminate most Kotlin initialize timeout pain early.
