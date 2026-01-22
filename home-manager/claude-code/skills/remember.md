---
name: remember
description: Update the project's CLAUDE.md with learnings from the current session (corrections, gotchas, patterns, workarounds)
---

# Remember Learnings

Analyze the current conversation to identify learnings that should be persisted to CLAUDE.md.

## Types of Learnings to Capture

1. **Corrections** - Where the user corrected my assumptions or approach
2. **Gotchas** - Non-obvious issues discovered during troubleshooting
3. **Patterns** - New configuration patterns or conventions established
4. **Workarounds** - Solutions to specific problems worth remembering
5. **Preferences** - User preferences for code style, tooling, or workflow

## Process

1. Review the entire conversation for learnings worth persisting
2. Read the current CLAUDE.md (if it exists) to understand structure and avoid duplicates
3. If no CLAUDE.md exists, ask the user if they want to create one
4. Categorize each learning and draft the text to add
5. Present ALL proposed additions to the user for review using AskUserQuestion
6. Only after explicit approval, write the changes to CLAUDE.md
7. Confirm what was added

## Interactive Confirmation

CRITICAL: Always use AskUserQuestion to get explicit approval before writing to CLAUDE.md.

Present learnings in this format:

**Proposed additions to CLAUDE.md:**

### Section: [Section Name]
```
[Exact text to add]
```

Then use AskUserQuestion with options:
- "Add all" - Add all proposed learnings
- "Select specific" - Let user choose which learnings to add
- "Edit first" - Show the learnings and let user suggest modifications
- "Cancel" - Don't add anything

If user selects "Select specific", present each learning individually with yes/no options.

If user selects "Edit first", ask what they'd like to change and incorporate feedback.

## Categorization

When the type of learning is ambiguous, ask the user:

"What type of learning is this?"
- Gotcha/Quirk - Non-obvious issue or edge case
- Pattern - Recommended approach or convention
- Preference - Personal style or workflow choice
- Workaround - Solution to a specific problem

## Guidelines

- Be concise - capture the essence, not the full conversation
- Be specific - include file paths, commands, and concrete details
- Explain "why" not just "what"
- Skip trivial or one-off issues unlikely to recur
- Match the formatting style of existing CLAUDE.md content
- Place learnings in the most appropriate existing section, or propose a new section
- If no meaningful learnings are found, tell the user honestly

## When No Learnings Found

If the conversation contains no learnings worth persisting, respond:

"I reviewed the conversation but didn't find any learnings that should be persisted to CLAUDE.md. This typically happens when:
- The session was exploratory or informational
- Issues encountered were one-off or trivial
- Solutions used were already documented

Is there something specific from this session you'd like me to capture?"
