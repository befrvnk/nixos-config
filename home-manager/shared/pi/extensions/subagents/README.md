# subagents

User-controlled code review subagents for Pi.

## Commands

- `/review` — run the fixed review pair against uncommitted changes, staged changes, a selected base branch, or a commit
- `/subagent <id>` — show detailed history for one review task from the current session

The extension does not expose agent-facing tools. The main agent performs its own repository and documentation research with its regular tools.

## Review workflow

Review is user-controlled via `/review` and runs the fixed reviewer pair:

- `github-copilot/claude-opus-4.8`
- `github-copilot/gemini-3.1-pro-preview`

A preliminary change brief uses `github-copilot/gpt-5.6-luna` to orient the reviewers.

Supported command forms:

- `/review`
- `/review uncommitted`
- `/review staged`
- `/review branch main`
- `/review commit abc1234`
- `/review staged --extra "focus on rollback safety"`
- `/review branch main --extra "look for dependency churn"`

Interactive `/review` supports searchable target selection and a cancellable loader. RPC mode uses Pi's standard selection requests; JSON and print modes require an explicit target.

After a successful or partial review, the rendered findings are stored as a custom message in the main agent context so the user can immediately ask it to apply or address the review.

If a real `REVIEW_GUIDELINES.md` exists next to the repository's real `.pi/` directory, its contents are appended only for trusted projects. Discovery stops at the canonical repository root and ignores symlinked external guidance.

Review gathers the repository root, changed files, status, diff statistics, a bounded diff preview, and relevant untracked files. Uncommitted and staged reviews in an unborn repository compare against the empty tree.

Results contain:

- `## Summary`
- `## Verdict`
- `## Findings`
- `## Non-blocking Callouts`
- `## Next Steps`

The final output includes consensus, output-quality and agreement summaries, deduplicated findings, callouts, suggested follow-ups, and per-reviewer details. Malformed output is preserved for inspection, and each reviewer gets one strict formatting retry when necessary.

## Runtime

The shared runtime provides:

- isolated in-process child sessions
- parallel reviewer execution
- GitHub Copilot model resolution
- abort propagation
- run state and recent history
- widget/status UI
- guarded read-only child tools

Child sessions use `createAgentSession`, `DefaultResourceLoader`, and `SessionManager.inMemory`. Extensions and themes are disabled in child resource loaders.

## Tool and path constraints

Review children use guarded versions of:

- `read`
- `grep`
- `find`
- `ls`
- `bash`

Structured file tools are confined to the canonical inspection root. The bash tool is limited to Git metadata inspection and `pwd`; it blocks shell composition, redirection, expansion, environment assignments, helper execution, write-capable options, and mutating Git forms.

Repository context and untracked previews do not follow symlinks. Runtime and system paths such as `/$bunfs`, `/proc`, `/sys`, and `/dev` are rejected after path normalization.

These checks are defense in depth, not an OS-level sandbox.

## Model policy

Subagents only support GitHub Copilot models declared in `model-policy.ts`. The allowed set contains the fixed reviewers and the change-brief model.

## Status and history

Task IDs appear in the widget and result rendering in short form, such as `abc123/1`. `/subagent` accepts either a full task ID or an unambiguous short ID.

Run state and detailed task history are session-local and are not persisted across sessions.
