# Search Tools

Provider-neutral pi tools for external web and code-context search.

## Tools

- `web_search` - current web research for documentation, official references, release notes, recent changes, project pages, issues, and technical topics beyond the model cutoff.
- `web_fetch` - fetch and read a specific HTTP(S) URL, returning markdown, text, or HTML with metadata and truncation.
- `code_search` - implementation-oriented API, SDK, framework, and library documentation with code examples.

The current implementation uses Exa's hosted MCP endpoint internally, but keeps provider-specific naming out of the model-facing tool names.

## Notes

- `web_search` defaults to an overview workflow that runs docs, general, repo/release, and recency-focused passes when appropriate.
- `web_search` returns Markdown with the searched queries and source URLs only, omitting Exa's page-content snippets so the provenance stays clear and compact.
- `web_fetch` is the follow-up content reader for specific URLs. Every redirect hop is DNS-resolved, checked against IPv4 and IPv6 special-use ranges, and connected through a pinned validated address while preserving the original HTTPS hostname and SNI. Mixed public/private DNS answers are rejected.
- `web_fetch` enforces the 5 MiB limit while streaming, sanitizes unsafe controls and malformed HTML entities, and validates every redirect independently. Cancellation covers DNS waiting, connection, redirects, and body streaming.
- All three tools cap model-facing output at 50 KiB or 2,000 lines. Complete output is written to an owner-private temporary file when either that limit or `web_fetch.maxCharacters` omits content. The returned path can be inspected with `read`.
- The TUI renders only compact metadata so fetched page bodies do not flood the visible conversation.
- `code_search` uses the code-context endpoint and is meant for external library/API usage examples, not local repository search.
- `code_search` also returns and renders Markdown, including syntax-highlighted fenced code blocks when the provider includes them.
- Prefer local tools such as `grep`, `find`, and LSP tools for searching the current checkout.
