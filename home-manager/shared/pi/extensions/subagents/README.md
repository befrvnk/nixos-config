# subagents

Shared subagent extension for pi.

It currently exposes:

## Agent-facing tools

- `explore`
- `explore_status`

## User-facing commands

- `/review` — run the fixed review pair against:
  - uncommitted changes
  - staged changes
  - a selected base branch
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

## Layout

- `index.ts` wires commands, tools, and shared orchestration
- `workflows/explore/` contains the explore prompt, schema, and rendering/parsing logic
- `workflows/review/` contains the review prompt, config, and rendering/parsing logic
- the top-level shared files remain the reusable subagent runtime used by both workflows

## Tooling and model constraints

Child runs are intentionally read-only and use guarded versions of:

- `read`
- `grep`
- `find`
- `ls`
- `bash`

The bash tool is restricted to read-only inspection commands and blocks shell output redirection, command substitution, and write-capable git subcommands.

Subagents only support these **GitHub Copilot** models:

- `github-copilot/claude-opus-4.6`
- `github-copilot/claude-sonnet-4.6`
- `github-copilot/gemini-3.1-pro-preview`
- `github-copilot/gpt-5.4-mini`
- `github-copilot/gpt-5.4`

## Explore workflow

`explore` is agent-controlled and optimized for:

- repository investigation
- docs/source lookup
- compressed context gathering
- parallel information collection

The agent may choose one allowed model per task. If omitted, the default is:

- `github-copilot/gpt-5.4-mini`

Examples:

- one explore task with an explicit model
- multiple parallel tasks with mixed models
- repo scan + docs lookup + upstream inspection in parallel

It is not for formal audits or severity-ranked bug finding; `/review` is user-triggered.

It returns structured markdown with:

- `## Summary`
- `## Sources`
- `## Key Findings`
- `## Next Steps`

## Review workflow

Review is user-controlled via `/review` and always runs the fixed reviewer pair:

- `github-copilot/claude-opus-4.6`
- `github-copilot/gemini-3.1-pro-preview`

Current command forms:

- `/review`
- `/review uncommitted`
- `/review staged`
- `/review branch main`

Interactive `/review` currently supports:

1. review uncommitted changes
2. review staged changes
3. review against a base branch

Interactive review runs use a cancellable loader UI; press `Esc` to abort an in-progress review.

Base-branch review compares the current working tree against the merge base with the selected branch.

Review gathers:

- repository root
- changed files
- `git status --short`
- diff stat
- diff preview (truncated when large)
- untracked working-tree files when relevant

When a repository has an unborn `HEAD`, uncommitted/staged review falls back to diffing against the empty tree so first-commit changes can still be inspected.

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
- `/subagent <id>` shows the detailed per-task history for any subagent task from the current session

Task IDs are shown in the widget and result rendering using a short form such as `abc123/1`.
The command accepts either the full task id or the displayed short id, as long as it is unambiguous.

Run tracking and subagent history are session-local and not persisted across sessions.
