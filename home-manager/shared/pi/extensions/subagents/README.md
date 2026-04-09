# subagents

Shared subagent extension for pi.

It currently exposes two read-only workflows built on the same subagent runtime:
- `explore` / `explore_status`
- `review` / `review_status`

It also adds a session-local command:
- `/subagent <id>` — show detailed history for one subagent task from the current session

## Shared runtime

Both workflows share the same subagent engine for:
- isolated child agent sessions
- parallel task execution
- GitHub Copilot model resolution
- abort propagation
- run state tracking
- recent run history
- widget/status UI
- guarded read-only child tools

Any runtime fix or improvement applies to both explore and review.

## Tooling and model constraints

Child runs are intentionally read-only and use guarded versions of:
- `read`
- `grep`
- `find`
- `ls`
- `bash`

The bash tool is restricted to read-only inspection commands and blocks shell output redirection, command substitution, and write-capable git subcommands.

Subagents only support models available through **GitHub Copilot**.
- If you omit `model`, the subagent inherits the current session model when it is a GitHub Copilot model.
- If the current model is not from GitHub Copilot, the subagent falls back to `github-copilot/gpt-5.4` when available.
- Explicit model overrides must also resolve to `github-copilot/...`.

## Explore workflow

`explore` is optimized for:
- repository investigation
- docs/source lookup
- compressed context gathering
- parallel information collection

It returns structured markdown with:
- `## Summary`
- `## Sources`
- `## Key Findings`
- `## Next Steps`

## Review workflow

`review` is optimized for:
- reviewing the current git changes
- running multiple reviewer models in parallel
- collecting independent reviewer opinions
- surfacing actionable findings

It gathers:
- repository root
- changed files
- `git status --short`
- diff stat
- diff preview (truncated when large)
- untracked working-tree files when reviewing the working tree

When a repository has an unborn `HEAD`, review falls back to diffing against the empty tree so first-commit changes can still be inspected.

Fixed review models:
- `github-copilot/claude-opus-4.6`
- `github-copilot/gemini-3.1-pro-preview`

These are enforced by the tool. The calling agent cannot choose different review models.

It returns structured markdown with:
- `## Summary`
- `## Findings`
- `## Next Steps`

## Guarding and scope discipline

The child tool guard is intentionally small and pragmatic.
It blocks obviously irrelevant runtime/system paths such as:
- `/$bunfs`
- `/proc`
- `/sys`
- `/dev`

Path validation normalizes both absolute paths and relative traversals such as `../../proc/...` before applying the denylist.

This is not a full sandbox. Focus still primarily comes from:
- the workflow prompt
- the task body
- read-only tool selection
- parent-run abort handling

## Runtime assumptions

This extension is built against pi's in-process agent-session APIs:
- `createAgentSession`
- `DefaultResourceLoader`
- `SessionManager.inMemory`

Child runs are started with extensions and themes disabled through the resource loader so they stay minimal and predictable.

## Status inspection

- `explore_status` shows only explore runs
- `review_status` shows only review runs
- `/subagent <id>` shows the detailed per-task history for a specific subagent task

Task IDs are shown in the widget and result rendering using a short form such as `abc123/1`.
The command accepts either the full task id or the displayed short id, as long as it is unambiguous.

Run tracking and subagent history are session-local and not persisted across sessions.
