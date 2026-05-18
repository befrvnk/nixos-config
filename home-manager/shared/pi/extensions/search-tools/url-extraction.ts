export function extractUrlsFromMcpResult(result: unknown): string[] {
  const explicitUrls = new Set<string>();
  const textValues: string[] = [];

  collectUrlCandidates(result, explicitUrls, textValues);

  const sourceUrls = new Set<string>(explicitUrls);
  for (const text of textValues) {
    for (const url of extractSourceUrlsFromText(text)) sourceUrls.add(url);
  }

  if (sourceUrls.size > 0) return Array.from(sourceUrls);

  const fallbackUrls = new Set<string>();
  for (const text of textValues) {
    for (const url of extractAllUrlsFromText(text)) fallbackUrls.add(url);
  }

  return Array.from(fallbackUrls);
}

function collectUrlCandidates(value: unknown, explicitUrls: Set<string>, textValues: string[]): void {
  if (typeof value === "string") {
    textValues.push(value);
    return;
  }

  if (Array.isArray(value)) {
    for (const item of value) collectUrlCandidates(item, explicitUrls, textValues);
    return;
  }

  if (value == null || typeof value !== "object") return;

  for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
    if (typeof entry === "string") {
      if (isUrlLikeKey(key)) {
        for (const url of extractAllUrlsFromText(entry)) explicitUrls.add(url);
      } else if (isSearchTextKey(key)) {
        textValues.push(entry);
      }
      continue;
    }

    collectUrlCandidates(entry, explicitUrls, textValues);
  }
}

function isUrlLikeKey(key: string): boolean {
  return /^(url|uri|href|link|source|sourceUrl|canonicalUrl)$/i.test(key);
}

function isSearchTextKey(key: string): boolean {
  return /^(text|content|markdown|summary|snippet|description)$/i.test(key);
}

function extractSourceUrlsFromText(text: string): string[] {
  const normalized = normalizeEscapedSlashes(text);
  const urls = new Set<string>();
  const labelledUrlPattern = /(?:^|\n)\s*(?:[-*]\s*)?(?:url|source|link)\s*:\s*(?:<|\[[^\]\n]+\]\()?((?:https?:\/\/)[^\s<>"'`\\]+)/gim;
  const leadingMarkdownLinkPattern = /(?:^|\n)\s*(?:#{1,6}\s*)?(?:(?:[-*]|\d+[.)])\s*)?\[[^\]\n]+\]\(((?:https?:\/\/)[^\s<>"'`\\]+)\)/gim;

  collectRegexUrls(normalized, labelledUrlPattern, urls);
  collectRegexUrls(normalized, leadingMarkdownLinkPattern, urls);

  return Array.from(urls);
}

function extractAllUrlsFromText(text: string): string[] {
  const normalized = normalizeEscapedSlashes(text);
  const urls = new Set<string>();
  collectRegexUrls(normalized, /https?:\/\/[^\s<>"'`\\]+/gi, urls);
  return Array.from(urls);
}

function collectRegexUrls(text: string, pattern: RegExp, urls: Set<string>): void {
  for (const match of text.matchAll(pattern)) {
    const candidate = match[1] ?? match[0];
    const url = cleanupUrl(candidate);
    if (url) urls.add(url);
  }
}

function normalizeEscapedSlashes(text: string): string {
  return text.replace(/\\\//g, "/");
}

function cleanupUrl(url: string): string {
  let cleaned = url.trim();
  cleaned = cleaned.replace(/[.,;:!?]+$/g, "");

  while (cleaned.endsWith(")") && countChar(cleaned, "(") < countChar(cleaned, ")")) cleaned = cleaned.slice(0, -1);
  while (cleaned.endsWith("]") && countChar(cleaned, "[") < countChar(cleaned, "]")) cleaned = cleaned.slice(0, -1);
  while (cleaned.endsWith("}") && countChar(cleaned, "{") < countChar(cleaned, "}")) cleaned = cleaned.slice(0, -1);

  return cleaned.startsWith("http://") || cleaned.startsWith("https://") ? cleaned : "";
}

function countChar(text: string, char: string): number {
  return Array.from(text).filter((item) => item === char).length;
}
