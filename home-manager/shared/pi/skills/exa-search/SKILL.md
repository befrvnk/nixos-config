---
name: exa-search
description: Web search via Exa AI with broader multi-pass overviews across docs, general web results, code, releases, and recent changes. Use for current documentation, release notes, official pages, and other web research beyond the model cutoff.
---

# Exa Search

Web search using Exa AI's hosted MCP endpoint. No browser or API key required.

By default, the main script runs a broader **overview workflow** so the agent gets more context from a single search command. It performs multiple Exa searches behind the scenes and groups the results into a single report.

## Search

```bash
~/.pi/agent/skills/exa-search/scripts/search.sh "query"                               # Broader overview (default)
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --focus docs                  # Only docs/reference pass
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --focus repo                  # GitHub / release / issue oriented pass
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --focus recent                # Recent updates pass with current-year hinting
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --single                      # One focused Exa query
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --results 6                   # More results per search pass
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --type deep                   # Force deep mode explicitly
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --livecrawl preferred         # Prefer fresh crawling
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --chars 12000                 # Increase context per search pass
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --json                        # Combined JSON for all passes
```

## Code / doc context

```bash
~/.pi/agent/skills/exa-search/scripts/code-search.sh "React useEffect cleanup examples"
~/.pi/agent/skills/exa-search/scripts/code-search.sh "Next.js partial prerendering configuration" --tokens 8000
~/.pi/agent/skills/exa-search/scripts/code-search.sh "Python pandas dataframe filtering" --json
```

This uses Exa's `get_code_context_exa` endpoint for implementation-oriented lookups across APIs, SDKs, and library docs.

## How the overview mode works

Unless `--single` is passed, `search.sh` runs a search plan:

1. **Official docs & references**
2. **General overview**
3. **Code, releases & issues**
4. **Recent updates** when the query looks time-sensitive (`latest`, `release`, `changelog`, etc.)

This keeps the surface area simple for the agent: one skill, one main search command, broader results.

## Focused modes

Use `--focus` when you already know the kind of result you want:

- `--focus docs` - official docs and references
- `--focus general` - broad web overview only
- `--focus repo` - GitHub / release / issue oriented results
- `--focus recent` - recent updates and announcements
- `--focus overview` - the default multi-pass workflow

`--single` is still available for a literal one-query Exa call.

## Constraint preservation

If the user includes constraints such as `site:`, repo names, versions, or years, the skill now keeps those constraints in the focused passes where they matter instead of broadening them away.

Examples:
- `"site:freeletics.github.io FlowRedux"`
- `"site:github.com freeletics FlowRedux releases"`
- `"latest Kotlin LSP release notes 2026"`

## Adaptive defaults

The defaults now depend on the mode:

- `overview`: `type=deep`, `livecrawl=preferred`, `results=5`, `chars=8000`
- focused / single lookups: lighter defaults for faster targeted results
- `recent` focus keeps `livecrawl=preferred`

You can still override everything explicitly.

## Query tips

Use a clear topic query first. The overview mode will broaden it automatically.

Examples:
- `"FlowRedux documentation"`
- `"Anthropic web search tool docs"`
- `"latest Kotlin LSP release notes"`
- `"site:freeletics.github.io FlowRedux"`
- `"site:github.com freeletics FlowRedux releases"`

Prefer `site:` when you already know the official domain. The skill will preserve that constraint in the relevant passes.

## Options

### `search.sh`

- `--overview` - Run the broader multi-pass workflow (default)
- `--single` - Run one focused Exa query only
- `--focus <overview|docs|general|repo|recent>` - Limit overview mode to a specific pass
- `--results <num>` - Number of results per search pass
- `--type <auto|fast|deep>` - Search mode
- `--livecrawl <fallback|preferred>` - Fresh crawl behavior
- `--chars <num>` - Maximum context characters per search pass
- `--json` - Print combined JSON instead of plain text

### `code-search.sh`

- `--tokens <num>` - Number of Exa code-context tokens to return (1000-50000, default: `5000`)
- `--json` - Print JSON instead of plain text

## Output format

```text
Exa research overview for: FlowRedux documentation
Mode: overview
Focus: overview
Per-search settings: results=5, type=deep, livecrawl=preferred, chars=8000
Combined search time: 123.4ms

Search plan:
- Official docs & references: FlowRedux documentation official documentation docs reference
- General overview: FlowRedux documentation
- Code, releases & issues: site:github.com FlowRedux documentation releases issues changelog

================================================================================
Official docs & references
Query: FlowRedux documentation official documentation docs reference
Search time: 40.1ms
================================================================================
...
```

## Recommended usage

- Use the default overview mode first when the goal is understanding a topic broadly.
- Use `--focus docs|repo|recent|general` when you already know the search intent.
- Use `--single` only when you want a literal one-query lookup.
- Use `code-search.sh` for API / SDK / library usage patterns and implementation-oriented docs.
- If results are still too thin, rerun with a clearer topic or a `site:` filter.
- For recent changes, include words like `latest`, `release`, `changelog`, or a year.

## When to use

- Searching for current documentation or API references
- Finding official project pages and release notes
- Getting a broader overview of a project, library, or tool
- Looking up recent announcements or changes
- Pulling code-context for APIs, SDKs, and libraries
- Web research where normal search engine HTML is noisy for agents
