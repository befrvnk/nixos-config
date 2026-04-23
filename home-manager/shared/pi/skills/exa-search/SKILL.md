---
name: exa-search
description: Web search via Exa AI with broader multi-pass overviews across docs, general web results, code, releases, and recent changes. Use for current documentation, release notes, official pages, and other web research beyond the model cutoff.
---

# Exa Search

Web search using Exa AI's hosted MCP endpoint. No browser or API key required.

By default, the script runs a broader **overview workflow** so the agent gets more context from a single search command. It performs multiple Exa searches behind the scenes and groups the results into a single report.

## Search

```bash
~/.pi/agent/skills/exa-search/scripts/search.sh "query"                               # Broader overview (default)
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --single                      # One focused Exa query
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --results 6                   # More results per search pass
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --type deep                   # Force deep mode explicitly
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --livecrawl preferred         # Prefer fresh crawling
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --chars 12000                 # Increase context per search pass
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --json                        # Combined JSON for all passes
```

## How the overview mode works

Unless `--single` is passed, the script runs a small search plan:

1. **Official docs & references**
2. **General overview**
3. **Code, releases & issues**
4. **Recent updates** when the query looks time-sensitive (`latest`, `release`, `changelog`, etc.)

This keeps the surface area simple for the agent: one skill, one script, broader results.

## Query tips

Use a clear topic query first. The overview mode will broaden it automatically.

Examples:
- `"FlowRedux documentation"`
- `"Anthropic web search tool docs"`
- `"latest Kotlin LSP release notes"`
- `"site:freeletics.github.io FlowRedux"`
- `"site:github.com freeletics FlowRedux releases"`

Prefer `site:` when you already know the official domain. The script will still add complementary passes around that topic.

## Options

- `--overview` - Run the broader multi-pass workflow (default)
- `--single` - Run one focused Exa query only
- `--results <num>` - Number of results per search pass (default: 5)
- `--type <auto|fast|deep>` - Search mode (default: `deep`)
- `--livecrawl <fallback|preferred>` - Fresh crawl behavior (default: `preferred`)
- `--chars <num>` - Maximum context characters per search pass (default: `8000`)
- `--json` - Print combined JSON instead of plain text

## Output Format

```text
Exa research overview for: FlowRedux documentation
Mode: overview
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
- Use `--single` only when you want a very narrow lookup or already know the exact source you want.
- If results are still too thin, rerun with a clearer topic or a `site:` filter.
- For recent changes, include words like `latest`, `release`, `changelog`, or a year.

## When to Use

- Searching for current documentation or API references
- Finding official project pages and release notes
- Getting a broader overview of a project, library, or tool
- Looking up recent announcements or changes
- Web research where normal search engine HTML is noisy for agents
