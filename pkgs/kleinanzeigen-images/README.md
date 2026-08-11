# kleinanzeigen-images

Downloads the public images embedded in a Kleinanzeigen listing and writes a `manifest.json` containing the local image paths and source URLs.

```sh
kleinanzeigen-images \
  --output ~/Downloads/kleinanzeigen \
  --max-images 12 \
  'https://www.kleinanzeigen.de/s-anzeige/...'
```

Without `--output`, images are written to a temporary directory. Use `--json` when another program needs the manifest on stdout.

The CLI accepts only public `https://www.kleinanzeigen.de/s-anzeige/...` listing URLs, downloads only images served by Kleinanzeigen' image host, follows at most five same-site redirects, and limits each image to 15 MiB by default. It does not use accounts, cookies, or anti-bot bypasses.
