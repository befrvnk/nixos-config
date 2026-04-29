# Subagents Extension: Updated Implementation Plan

## Implementation Handoff Summary

Use this summary first if you are implementing in a fresh session.

### What the user wants

- `review` must become **completely user-controlled**
- `explore` must remain **agent-controlled**
- the main agent must be able to spawn **multiple parallel explore subagents**
- the main agent must be able to choose the **explore model per task** from the strict whitelist
- `explore` must **not** automatically fan out every task into multiple fixed model runs
- the `/review` UX should copy the **option selection / selector flow** from the reference extension:
  - `https://github.com/mitsuhiko/agent-stuff/blob/main/pi-extensions/review.ts`
- we should copy only the **selection UX**, **not** the review-branch lifecycle, `/end-review`, or loop-fixing behavior

### Current branch status

The current branch already contains an intermediate refactor that is **not** the final desired behavior.
Most importantly, it currently:

- makes `explore` fan out into two fixed model runs
- removes model choice from `explore`
- still keeps review in the subagent tool architecture

Do **not** keep that design.
Reshape it into the target design from this plan.

### Final target architecture

#### Agent-facing
- `explore`
- `explore_status`

#### User-facing
- `/review`
- `/subagent <id>`

#### Not agent-facing anymore
- `review`
- `review_status`

### Allowed model whitelist for explore

Only the models centralized in `model-policy.ts` may be used for explore:

- `github-copilot/claude-opus-4.6`
- `github-copilot/claude-sonnet-4.6`
- `github-copilot/gemini-3.1-pro-preview`
- `FAST_EXPLORE_MODEL`
- `DEFAULT_EXPLORE_MODEL`

Recommended default when `model` is omitted:

- `DEFAULT_EXPLORE_MODEL`

### Fixed review models

Review must remain fixed to:

- `github-copilot/claude-opus-4.6`
- `github-copilot/gemini-3.1-pro-preview`

### Recommended implementation order

If time is limited, do these first:

1. restore flexible per-task `explore`
2. remove agent access to review
3. add `/review`
4. add selector UX for the most important review modes:
   - uncommitted
   - staged
   - base branch

### Minimum acceptable landing

A good first landing in the next session is:

- `explore` supports per-task model selection again
- `explore` no longer auto-fanouts
- the agent can launch multiple parallel explore tasks
- review is no longer agent-callable
- `/review` exists and runs the fixed review pair
- `/review` supports at least:
  - uncommitted
  - staged
  - base branch

This plan is for the next implementation session.
It supersedes the previous direction where `explore` always fanned out to a fixed pair of models.

## Goal

Split responsibilities cleanly:

- **`explore` stays agent-controlled**
- **`review` becomes completely user-controlled**

Desired outcome:

- The main agent can launch one or many `explore` subagents as needed
- The main agent can choose the explore model per task from a strict whitelist
- The user starts reviews explicitly through `/review`
- The agent no longer has the power to start reviews on its own

---

## Final UX / Control Model

### Agent-facing capabilities

The main agent should have access to:

- `explore`
- `explore_status`

The agent should **not** have access to:

- `review`
- `review_status`

### User-facing capabilities

The user should get:

- `/review`
- `/subagent <id>`

Optional later:

- `/review-status`

---

## Model Policy

### Allowed explore models

The main agent may choose **only** from this whitelist centralized in `model-policy.ts`:

- `github-copilot/claude-opus-4.6`
- `github-copilot/claude-sonnet-4.6`
- `github-copilot/gemini-3.1-pro-preview`
- `FAST_EXPLORE_MODEL`
- `DEFAULT_EXPLORE_MODEL`

### Explore model selection

Per task, the main agent may choose any allowed model.
Different parallel tasks may use different models.

Examples that should be supported:

- 2 web research tasks with different models
- 2 code-inspection tasks in different parts of the repo
- 4 mixed tasks running in parallel, each with its own chosen model

### Default explore model

Recommended fallback when `model` is omitted:

- `DEFAULT_EXPLORE_MODEL`

Important: **do not** inherit the current session model anymore.
The fallback should be predictable and cheap.

### Review model selection

Review remains fixed and user-only:

- `github-copilot/claude-opus-4.6`
- `github-copilot/gemini-3.1-pro-preview`

The user does not choose review models.
The command always runs the fixed pair.

---

## Current State in the Repo (Important)

The current working tree already contains an intermediate refactor from a previous session.
That refactor is **not** the desired final state.
The next implementation session should adjust it rather than build from scratch.

### Current state that must be changed

1. `explore` currently fans out each logical task into two fixed model runs
   - `FAST_EXPLORE_MODEL`
   - `github-copilot/claude-sonnet-4.6`

2. `explore` currently rejects model overrides from the caller

3. `explore` currently groups multiple child runs back into one logical result

4. `schemas.ts` currently removed the per-task `model` field for `explore`

5. `runner.ts` currently requires explicit fixed models for all subagent tasks

6. `review` is still exposed as a tool
   - This must change. Review must become user-only.

### Files currently affected by the intermediate refactor

- `home-manager/shared/pi/extensions/subagents/model-policy.ts`
- `home-manager/shared/pi/extensions/subagents/explore.ts`
- `home-manager/shared/pi/extensions/subagents/index.ts`
- `home-manager/shared/pi/extensions/subagents/schemas.ts`
- `home-manager/shared/pi/extensions/subagents/runner.ts`
- `home-manager/shared/pi/extensions/subagents/README.md`
- `home-manager/shared/pi/extensions/subagents/explore-prompt.ts`
- `home-manager/shared/pi/extensions/subagents/review-prompt.ts`
- `home-manager/shared/pi/extensions/subagents/review-config.ts`
- `home-manager/shared/pi/extensions/subagents/types.ts`

The new session should treat those changes as a partially-complete branch that needs to be reshaped.

---

## Reference Extension to Copy From

The user explicitly wants to borrow the **`/review` option selection UX** from:

- `https://github.com/mitsuhiko/agent-stuff/blob/main/pi-extensions/review.ts`

### What to copy

Copy/adapt these parts:

- `/review` as an interactive command
- preset selector UI
- direct argument parsing for fast-path usage
- supporting selectors/inputs for review targets
  - branch selector
  - commit selector
  - PR input
  - folder/path input
- optional custom review instructions toggle/input (recommended)

### What **not** to copy

Do **not** copy these workflow ideas:

- review branch/session state
- `/end-review`
- loop fixing / review-fix-review cycles
- automatic follow-up fix prompts
- navigation back to origin branch/session

We want only the **selection UX**, not the whole review-branch lifecycle.

---

# Phased Implementation Plan

## Phase 1 — Restore flexible agent-controlled `explore`

### Objective

Undo the fixed two-model fanout design and restore `explore` as a flexible agent tool.

### Desired behavior after Phase 1

- One explore task = one child run
- Multiple explore tasks = multiple child runs
- The main agent may choose the model per task from the whitelist
- If omitted, model defaults to `DEFAULT_EXPLORE_MODEL`
- `explore` remains read-only
- `explore_status` continues to work
- `review` may still exist temporarily during this phase, but Phase 2 removes it from agent control

### File-level plan

#### 1. `model-policy.ts`

Keep:

- allowed model whitelist
- fixed review pair

Change:

- remove `FIXED_EXPLORE_MODELS`
- add `DEFAULT_EXPLORE_MODEL`, derived from centralized model IDs

Suggested shape:

- `ALLOWED_SUBAGENT_MODELS`
- `isAllowedSubagentModel(model: string)`
- `DEFAULT_EXPLORE_MODEL`
- `FIXED_REVIEWERS`

#### 2. `schemas.ts`

Restore per-task explore model selection.

Expected `explore` schema shape:

```ts
{
  task?: string,
  model?: string,
  cwd?: string,
  tasks?: Array<{
    task: string,
    model?: string,
    cwd?: string,
  }>
}
```

Notes:

- do not reintroduce current-session-model wording
- wording should say model must resolve to an allowed GitHub Copilot model
- increase capacity beyond the current logical-task cap of 2

Recommended limits:

- `tasks.length <= 8`
- runtime concurrency limit can still remain smaller (for example 4)

#### 3. `explore.ts`

Undo the fixed-pair fanout and grouped rendering.

Remove or simplify:

- `buildExploreTasks()` that duplicates tasks across a fixed pair
- logical-task grouping helpers
- grouped result rendering

Return to a flatter model:

- each task result is rendered directly
- show model per task
- show summary / sources / key findings / next steps per task

This makes status/history consistent again.

#### 4. `index.ts`

For the `explore` tool:

- stop rejecting `model` overrides
- stop building duplicated child tasks
- pass through one child task per requested task
- if `model` is missing, inject `DEFAULT_EXPLORE_MODEL`

Update prompt guidelines to say:

- choose cheaper models for lightweight scans
- choose stronger models when synthesis is more important
- use multiple tasks when the work is naturally parallel
- `explore` is not for formal audits; `review` is user-triggered

#### 5. `runner.ts`

Keep whitelist enforcement.

Change model resolution policy:

- no current-session-model inheritance
- allow explicitly requested model if it is whitelisted
- allow omitted model only if caller already inserted the default
- no fixed-pair assumption

In other words:

- runner should resolve an explicit allowed model reference
- tool layer decides the default

### Acceptance criteria for Phase 1

- The main agent can run:

```json
{
  "task": "inspect x",
  "model": "github-copilot/claude-sonnet-4.6"
}
```

- The main agent can run:

```json
{
  "tasks": [
    { "task": "research topic A", "model": "<FAST_EXPLORE_MODEL>" },
    { "task": "research topic B", "model": "github-copilot/gemini-3.1-pro-preview" },
    { "task": "inspect module C", "model": "github-copilot/claude-opus-4.6" },
    { "task": "inspect module D", "model": "<DEFAULT_EXPLORE_MODEL>" }
  ]
}
```

- Disallowed models fail clearly
- No hidden 2-model fanout remains
- Final explore results are no longer grouped by synthetic logical tasks

---

## Phase 2 — Make `review` user-only and add `/review`

### Objective

Remove review from agent control and replace it with a user command.

### Desired behavior after Phase 2

- The agent no longer sees or invokes `review`
- The agent no longer sees or invokes `review_status`
- The user starts review with `/review`
- Review still runs the fixed reviewer pair
- The existing review backend is reused instead of rewritten

### File-level plan

#### 1. `index.ts`

Remove tool registration for:

- `review`
- `review_status`

Add command registration for:

- `/review`

Keep:

- `explore`
- `explore_status`
- `/subagent <id>`

#### 2. Reuse the existing review runtime

The `/review` command should reuse the current review execution flow:

- collect review context
- create fixed reviewer tasks
- execute reviewer subagents in parallel
- render review results using the existing review rendering

Do **not** create a second review engine.

If useful, factor command-related logic into a new file such as:

- `review-command.ts`

This is optional, but it may keep `index.ts` from becoming too large.

### Acceptance criteria for Phase 2

- `review` is no longer listed as an agent tool
- `review_status` is no longer listed as an agent tool
- `/review` exists and triggers the same fixed-pair review backend
- Reviews remain read-only

---

## Phase 3 — Copy the `/review` selector UX (adapted, not the full workflow engine)

### Objective

Adopt the preset-selector experience from the reference extension while keeping our simpler backend model.

### Important constraint

Copy only the **target selection UX**, not the review-branch lifecycle.

### `/review` command UX target

The command should support two entry modes:

#### A. No arguments → interactive selector

Show a preset selector modeled after the reference extension.

Recommended options:

1. Review uncommitted changes
2. Review staged changes
3. Review against a base branch
4. Review a commit
5. Review a pull request
6. Review a folder (or more)
7. Add/remove custom review instructions *(recommended utility item)*

#### B. Direct arguments → fast path

Support direct invocation forms such as:

- `/review uncommitted`
- `/review staged`
- `/review branch main`
- `/review commit abc1234`
- `/review pr 42`
- `/review folder home-manager/shared/pi`
- `/review folder home-manager/shared/pi modules`

### Recommended implementation details

#### 1. Selector behavior

Borrow the interaction style from the reference extension:

- a stable menu of preset options
- fuzzy searchable branch selector
- searchable commit selector
- PR input dialog/editor
- folder/path editor input

#### 2. Custom review instructions

Recommended but optional in first pass.

Behavior:

- menu item toggles add/remove custom instructions
- stored in extension state
- appended to every review prompt

Important: this is only a lightweight settings feature.
Do **not** add review-branch state or `/end-review`.

#### 3. Review target abstraction

Introduce a local `ReviewTarget` union for command-driven review.
Suggested shape:

```ts
type ReviewTarget =
  | { type: "uncommitted" }
  | { type: "staged" }
  | { type: "baseBranch"; branch: string }
  | { type: "commit"; sha: string; title?: string }
  | { type: "pullRequest"; prNumber: number; baseBranch: string; title: string; headBranch?: string }
  | { type: "folder"; paths: string[] };
```

### Important design note

The selector UX should be copied; the session/origin/loop machinery should **not**.

Do not add:

- `reviewOriginId`
- review branch state entries
- `/end-review`
- loop fixing
- automatic fix prompts

### Acceptance criteria for Phase 3

- `/review` without args opens a selector
- `/review staged` works directly
- `/review branch <name>` works directly
- selector subflows are usable and understandable
- no review-branch workflow was added

---

## Phase 4 — Extend the review backend to support all selected targets

### Objective

Make the review backend capable of serving all `/review` selector modes.

### Why this is needed

The current review backend is optimized for:

- working tree changes
- staged changes
- optional file subset

To fully support the selector UX, it needs to grow beyond the current `target: "working-tree" | "staged"` model.

### Recommended backend evolution

Refactor review context building so it works from `ReviewTarget` instead of only the current tool params shape.

Potential approach:

- keep the existing diff collection helpers where possible
- add a higher-level entry point such as:

```ts
collectReviewContextForTarget(pi, cwd, target, signal)
```

Then map each target type to concrete git operations.

### Proposed semantics by target

#### 1. `uncommitted`

Review the current working tree against `HEAD`, including:

- tracked unstaged changes
- staged changes
- untracked files (with preview)

This matches current working-tree behavior.

#### 2. `staged`

Review staged changes only.
Do not include unstaged tracked changes.
Do not include unrelated untracked files unless explicitly intended.

#### 3. `baseBranch`

Review the current branch against the merge base with the selected branch.

Recommended semantics:

- compute `merge-base(HEAD, branch)`
- diff from merge base to the current working tree state
- include local uncommitted changes as part of the current branch state

This makes the target useful as “review everything on my branch right now vs base branch.”

If that feels too broad during implementation, an acceptable narrower first version is:

- merge base to `HEAD`

But the semantics must be documented clearly.

#### 4. `commit`

Review exactly one commit.

Recommended data source:

- `git show --stat --unified=3 <sha>`
- changed files from that commit only

#### 5. `pullRequest`

This is the most complex target.

Recommended staged approach:

- prompt for PR number or URL
- use `gh pr view --json baseRefName,title,headRefName`
- decide implementation strategy

Possible strategies:

##### Strategy A — checkout-based (closest to reference extension)
- use `gh pr checkout <number>`
- review the checked-out PR branch against its base branch

Pros:
- simple to reason about once checked out
- closest to the reference extension UX

Cons:
- mutates repo state
- requires `gh`
- should probably confirm before checkout

##### Strategy B — no checkout, diff by refs
- fetch PR metadata and diff base/head refs directly if available locally/remotely

Pros:
- less intrusive

Cons:
- more implementation complexity

Recommendation:

- do **not** block the whole command on PR mode
- if PR mode is too much for the session, ship the other modes first and leave PR mode as Phase 4b

#### 6. `folder`

Review a snapshot of one or more folders/files, not necessarily a git diff.

This requires different semantics from diff review.

Prompt should clearly say:

- review the implementation under these paths
- focus on correctness, risks, and maintainability
- inspect the files directly
- this is a snapshot review, not a diff review

This mode should still use the fixed review pair.

### Acceptance criteria for Phase 4

- each selector mode maps to a concrete review context
- reviewers receive the right context for that mode
- commit review does not accidentally review unrelated working tree changes
- folder review clearly behaves as snapshot review, not diff review

---

## Phase 5 — Documentation, cleanup, and validation

### Objective

Make the new architecture understandable and verify behavior.

### Documentation updates

#### 1. `README.md` in the extension directory

Document the new split clearly:

- `explore` is agent-facing and flexible
- `review` is user-only via `/review`
- allowed model whitelist for explore
- fixed reviewer pair for review
- example `/review` usages

#### 2. Prompt text updates

##### `explore-prompt.ts`
Should say:

- choose the model appropriate for the task
- use cheaper models for quick scans
- use stronger models for deeper synthesis
- use parallel tasks when the work is naturally separable
- do not perform formal audits; reviews are user-triggered

##### `review-prompt.ts`
Should remain review-focused and fixed-pair oriented.

### Validation checklist

#### Explore validation

- agent can run single explore task with explicit model
- agent can run multiple explore tasks with mixed models
- omitted model defaults to `DEFAULT_EXPLORE_MODEL`
- non-whitelisted models fail clearly
- explore results and status reflect real child runs directly

#### Review validation

- `review` tool is gone from the agent tool list
- `/review` command works in interactive mode
- selector opens and is usable
- `/review staged` works
- `/review branch main` works
- fixed reviewer pair is always used
- no review-branch lifecycle was introduced accidentally

### Cleanup note

There are still some Biome warnings in the current branch around generic typing and `any` usage.
These are not the primary functional goal, but if the new session is already reshaping the files, it should clean up obvious ones where practical.
At minimum:

- avoid introducing new `any`s
- prefer clear local types for command/renderer payloads

---

# Recommended Implementation Order

If the next session wants the safest order, use this sequence:

1. **Phase 1** — restore flexible `explore`
2. **Phase 2** — remove review from agent tool surface and add `/review`
3. **Phase 3** — add selector UX and direct arg parsing
4. **Phase 4** — expand target support as far as time allows
5. **Phase 5** — docs and validation

If time is limited, the minimum useful landing is:

- flexible `explore`
- `/review` command
- review modes: uncommitted + staged + base branch

Then commit/PR/folder can follow in a later pass.

---

# Summary of Non-Negotiable Requirements

The next session should preserve these requirements:

1. **Review must be user-controlled only**
2. **Explore must be agent-controlled and flexible**
3. **Explore must not auto-fanout across fixed model pairs**
4. **Explore model choice must come from the whitelist**
5. **The agent must be able to launch multiple parallel explore tasks**
6. **The `/review` selector UX should be copied from the reference extension in spirit**
7. **Do not copy review-branch lifecycle or loop-fixing behavior**

---

# Useful File Paths

Main extension directory:

- `home-manager/shared/pi/extensions/subagents/`

Likely files to edit:

- `home-manager/shared/pi/extensions/subagents/model-policy.ts`
- `home-manager/shared/pi/extensions/subagents/explore.ts`
- `home-manager/shared/pi/extensions/subagents/index.ts`
- `home-manager/shared/pi/extensions/subagents/review.ts`
- `home-manager/shared/pi/extensions/subagents/schemas.ts`
- `home-manager/shared/pi/extensions/subagents/runner.ts`
- `home-manager/shared/pi/extensions/subagents/explore-prompt.ts`
- `home-manager/shared/pi/extensions/subagents/review-prompt.ts`
- `home-manager/shared/pi/extensions/subagents/README.md`

Potential new file if helpful:

- `home-manager/shared/pi/extensions/subagents/review-command.ts`

Reference implementation for selector UX:

- `https://github.com/mitsuhiko/agent-stuff/blob/main/pi-extensions/review.ts`
