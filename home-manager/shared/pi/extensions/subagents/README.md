# subagents

Shared subagent extension for pi.

It currently exposes:

## Agent-facing tools

- `explore`
- `explore_status`

## User-facing commands

- `/explore-fresh [fast|balanced|deep] <task>` — explicitly authorize a new independent exploration after reviewing any matching cached run
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

Any runtime fix or improvement applies to both explore and review. Exploration additionally has exact single-flight deduplication, conservative near-duplicate reuse, session budgets, and a branch-aware result cache.

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

The bash tool accepts one restricted inspection command per call. It blocks shell composition, redirection, expansion, environment assignments, helper execution, write-capable command options, and mutating Git forms. Review subagents additionally limit bash to Git metadata and `pwd`, using canonical-root-confined structured tools for file inspection. This validation is defense in depth, not an OS-level sandbox.

Subagents only support the **GitHub Copilot** models configured in `model-policy.ts`.
The model IDs are centralized in `SUBAGENT_MODEL_IDS`; changing explore intent models should only require updating the explore entries there.

## Explore workflow

`explore` is agent-controlled and optimized for:

- repository investigation
- docs/source lookup
- compressed context gathering
- parallel information collection

The agent does **not** choose raw model IDs anymore.
Instead it can provide an optional intent per task:

- `fast`
- `balanced` (default/fallback)
- `deep`

The extension maps those intents to safe internal GitHub Copilot model profiles from `model-policy.ts`.
Current mapping:

- `fast` → `FAST_EXPLORE_MODEL` (`gpt-5.6-luna`) with medium thinking
- `balanced` → `DEFAULT_EXPLORE_MODEL` (`gpt-5.6-terra`) with medium thinking
- `deep` → `DEEP_EXPLORE_MODEL` (`gpt-5.6-sol`) with high thinking

If intent is omitted or invalid, `explore` falls back to `balanced` automatically.

Equivalent active calls join one shared run. Successful exact matches are reused for five minutes, while failed or aborted matches have a 30-second retry cooldown. Substantially similar requests reuse prior findings rather than launching another worker. Cache keys include canonical working directories, resolved model/thinking profiles, and a conservative workspace revision. Successful `edit`, `write`, and `bash` results advance a branch-persisted workspace generation so cached repository findings are invalidated.

Only one explore workflow may be active at a time; independent perspectives should be expressed through one `tasks` array. The cache is limited to ten entries and 2 MiB, and new runs stop after one million tracked child tokens in a session. Cache state is restored from the active branch on session start and tree navigation. A deliberate rerun cannot be requested by the agent-facing tool: the user must invoke `/explore-fresh`, which shows matching run age and token cost before confirmation in interactive modes.

Examples:

- one explore task with the default or an explicit intent
- multiple parallel tasks with mixed intents
- repo scan + docs lookup + upstream inspection in parallel

It is not for formal audits or severity-ranked bug finding; `/review` is user-triggered.

It returns structured markdown with:

- `## Summary`
- `## Sources`
- `## Key Findings`
- `## Next Steps`

## Review workflow

Review is user-controlled via `/review` and always runs the fixed reviewer pair:

- `github-copilot/claude-opus-4.8`
- `github-copilot/gemini-3.1-pro-preview`

Current command forms:

- `/review`
- `/review uncommitted`
- `/review staged`
- `/review branch main`
- `/review commit abc1234`
- `/review staged --extra "focus on rollback safety"`
- `/review branch main --extra "look for dependency churn"`

Interactive `/review` currently supports:

1. review uncommitted changes
2. review staged changes
3. review against a base branch
4. review a commit

TUI review uses a smart default target, searchable branch and commit pickers, propagated input focus, and a cancellable loader. RPC mode uses Pi's standard selection requests instead of terminal components; JSON and print modes require an explicit target.

After a successful or partial review, the rendered findings are stored as a custom message that participates directly in the main agent context, so you can immediately ask it to apply or address the review.

`/review ... --extra "..."` appends one-off review focus instructions to the fixed reviewer pair.

If a real `REVIEW_GUIDELINES.md` file exists next to the repository's real `.pi/` directory, its contents are appended only for trusted projects. Discovery stops at the canonical repository root and ignores symlinked external guidance.

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
- `## Verdict`
- `## Findings`
- `## Non-blocking Callouts`
- `## Next Steps`

Rendered review results include a top-level consensus section with a rolled-up verdict, an output-quality summary, a reviewer-agreement summary, deduplicated findings, non-blocking callouts, and suggested follow-ups, followed by per-reviewer details.

If a reviewer returns malformed or partially structured output, the workflow preserves it, marks the structured-format quality, and includes a fenced preserved-raw-output section for manual inspection. Review subagents also get one strict formatting retry when the first answer drifts from the required schema.

## Guarding and scope discipline

Review paths are canonicalized and confined to the selected inspection root. Repository context and untracked previews do not follow symlinks, preventing external target contents from entering review prompts.

The child tool guard is intentionally conservative but remains application-level validation.
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
