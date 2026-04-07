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
