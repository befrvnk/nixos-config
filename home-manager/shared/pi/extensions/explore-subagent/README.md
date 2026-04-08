# explore-subagent

Minimal v1 exploration subagents for pi.

Scope:
- one generic exploration subagent model
- sync execution only
- single-task and parallel-task modes
- read-only exploration tools
- live progress updates during execution
- pi-subagents-style live widget/status UI for active tasks
- final results returned in a structured, synthesis-friendly format
- session-local status inspection via `explore_status`

Tools:
- `explore` — run one or more isolated exploration tasks
- `explore_status` — inspect active and recent exploration runs in the current session

Model selection:
- Single mode: pass `model` to choose a specific subagent model.
- Parallel mode: pass `model` per task.
- If `model` is omitted, the subagent inherits the current session model.

Design constraints:
- no async/background mode
- no mutating subagents
- no saved agent catalog
- no chains

Guarding and scope discipline:
- Child runs use guarded read-only exploration tools in-process.
- The guard is intentionally generic, not repo-bound.
- It blocks a short denylist of obviously irrelevant runtime/system paths such as `/$bunfs`, `/proc`, `/sys`, and `/dev`.
- This is a pragmatic anti-wandering guard, not a full sandbox.
- Task focus still primarily comes from prompt guidance, tool limits, and parent-run abort handling.

Runtime assumptions:
- Built against pi's current in-process agent-session APIs (`createAgentSession`, `DefaultResourceLoader`, `SessionManager.inMemory`).
- Child runs are started with `noExtensions` and `noThemes` behavior through the resource loader so they stay minimal and predictable.
- The child tool surface is limited to the built-in read-only exploration tools: `read`, `grep`, `find`, `ls`, and `bash`.
- `bash` availability still depends on the parent environment, since the guard narrows usage but does not replace the underlying shell.

The subagent prompt is optimized for information gathering and context compression. It instructs the child agent to return structured markdown with:
- `## Summary`
- `## Sources`
- `## Key Findings`
- `## Next Steps`

## v1 complete

`explore-subagent` v1 is complete as a minimal exploration-focused subagent extension for pi.

### v1 scope
- one generic exploration subagent
- sync-only execution
- single-task and parallel-task modes
- read-only child tools
- optional model override
- live widget/status visibility
- per-task UI identity
- structured result return
- session-local run inspection via `explore_status`

### v1 non-goals
- background/async execution
- editing or mutating child agents
- saved agent catalogs
- multiple specialized subagent roles
- persistent run history across sessions
- repo-bound sandboxing
- complex orchestration or steering flows

### Why this is enough for now
This version solves the main workflow need:
- delegate focused investigation
- preserve parent context
- keep UI observable
- return useful compressed findings

It is intentionally small, understandable, and easier to maintain than a broader subagent framework.

## Future ideas

Only revisit these after real usage shows they’re worth it.

### Potential v2+ ideas
- optional per-call timeout control
- optional max-turn limits
- resumable or background runs
- richer `explore_status get` views
- better source normalization/deduplication
- explicit web-search integration path
- lightweight result caching
- export/shareable run transcripts
- user-configurable guard policy
- optional specialized exploration modes

### Things to validate in real use first
- whether long-running broad tasks remain reliable enough
- whether `/dev`/path guard behavior is ever too strict
- whether model override needs better disambiguation UX
- whether widget/task-message balance feels right over time
- whether `explore_status` needs more session memory or persistence
- whether parallel limit `4` is the right default

### Good rule for future expansion
Add surface area only when repeated real tasks clearly justify it.
If a feature does not improve:
- exploration quality
- visibility
- reliability
- or simplicity

then it probably does not belong in this extension.
