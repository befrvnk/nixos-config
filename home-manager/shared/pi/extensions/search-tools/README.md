# Search Tools

Provider-neutral pi tools for external web and code-context search.

## Tools

- `web_search` - current web research for documentation, official references, release notes, recent changes, project pages, issues, and technical topics beyond the model cutoff.
- `code_search` - implementation-oriented API, SDK, framework, and library documentation with code examples.

The current implementation uses Exa's hosted MCP endpoint internally, but keeps provider-specific naming out of the model-facing tool names.

## Notes

- `web_search` defaults to an overview workflow that runs docs, general, repo/release, and recency-focused passes when appropriate.
- `code_search` uses the code-context endpoint and is meant for external library/API usage examples, not local repository search.
- Prefer local tools such as `grep`, `find`, and LSP tools for searching the current checkout.
