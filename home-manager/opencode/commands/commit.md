---
description: Create a commit using conventional commit format
---

You are tasked with creating a git commit following the Conventional Commits specification.

# Conventional Commits Format

Conventional Commits follow this structure:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Commit Types

- **feat**: A new feature
- **fix**: A bug fix
- **docs**: Documentation only changes
- **style**: Changes that don't affect code meaning (white-space, formatting, etc)
- **refactor**: Code change that neither fixes a bug nor adds a feature
- **perf**: Performance improvement
- **test**: Adding missing tests or correcting existing tests
- **build**: Changes to build system or external dependencies
- **ci**: Changes to CI configuration files and scripts
- **chore**: Other changes that don't modify src or test files
- **revert**: Reverts a previous commit

## Scope (optional)

The scope provides additional context, e.g., `feat(parser):`, `fix(auth):`, `docs(readme):`

## Breaking Changes

Breaking changes are indicated by:
- Adding `!` after type/scope: `feat!:` or `feat(api)!:`
- Adding `BREAKING CHANGE:` footer

## Examples

```
feat: add user authentication

Implement JWT-based authentication system with refresh tokens.

- Add login and logout endpoints
- Implement token validation middleware
- Add user session management
```

```
fix(api): prevent race condition in data fetching

Add mutex lock to ensure thread-safe access to shared cache.

Fixes #123
```

```
docs: update installation instructions

Add NixOS-specific setup steps and troubleshooting section.
```

```
refactor!: redesign configuration API

BREAKING CHANGE: Configuration now uses YAML instead of JSON.
Migration guide available in MIGRATION.md
```

# Your Task

1. **Review changes**: Run `git status` and `git diff` to see what has changed
2. **Analyze changes**: Understand what was modified and why
3. **Choose type**: Select the appropriate conventional commit type
4. **Write description**: Create a concise, imperative mood description (e.g., "add feature" not "added feature")
5. **Add body** (if needed): Provide more context for complex changes
6. **Stage files**: Add relevant files with `git add`
7. **Create commit**: Use `git commit -m` with your conventional commit message
8. **Confirm**: Show the commit hash and message after creation

## Important Guidelines

- Use imperative mood in description ("add" not "adds" or "added")
- Keep description under 72 characters when possible
- Don't end description with a period
- Body should explain what and why, not how
- Reference issue numbers when applicable
- Ask for clarification if the changes are unclear or span multiple types

Now, please review the current git status and create an appropriate conventional commit.
