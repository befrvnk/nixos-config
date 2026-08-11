# kleinanzeigen

A Go command-line client for Kleinanzeigen. The initial implementation provides safe public listing-gallery downloads; authenticated search and messaging are added incrementally only after their protocol flows are verified end to end.

```sh
kleinanzeigen images \
  'https://www.kleinanzeigen.de/s-anzeige/...'
```

The `images` command downloads only the listing gallery, not images from recommended ads. By default, downloaded files are written to a temporary directory. Use `--output <directory>` to retain them.
