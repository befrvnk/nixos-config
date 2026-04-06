---
name: exa-search
description: Web search via Exa AI. Use for current documentation, release notes, official pages, and other web research beyond the model cutoff. Lightweight, no browser required.
---

# Exa Search

Web search using Exa AI's hosted MCP endpoint. No browser or API key required.

## Search

```bash
~/.pi/agent/skills/exa-search/scripts/search.sh "query"                               # Basic search
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --results 10                  # More results
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --type deep                   # More comprehensive search
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --livecrawl preferred         # Prefer fresh crawling
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --chars 4000                  # Limit returned context
~/.pi/agent/skills/exa-search/scripts/search.sh "query" --json                        # Raw JSON output
```

### Query tips

Use precise queries. Prefer `site:` when looking for official docs.

Examples:
- `"FlowRedux documentation"`
- `"site:freeletics.github.io FlowRedux"`
- `"site:github.com freeletics FlowRedux releases"`
- `"site:docs.anthropic.com web search tool"`

### Options

- `--results <num>` - Number of results (default: 8)
- `--type <auto|fast|deep>` - Search mode (default: `auto`)
- `--livecrawl <fallback|preferred>` - Fresh crawl behavior (default: `fallback`)
- `--chars <num>` - Maximum context characters
- `--json` - Print parsed JSON instead of plain text

## Output Format

```text
Exa search for: FlowRedux documentation
Search time: 123.4ms

Title: FlowRedux
URL: https://freeletics.github.io/FlowRedux/
Published: N/A
Author: Freeletics
Highlights:
...
```

## When to Use

- Searching for current documentation or API references
- Finding official project pages and release notes
- Looking up recent announcements or changes
- Web research where normal search engine HTML is noisy for agents
