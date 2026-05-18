export type WebFetchFormat = "markdown" | "text" | "html";

export interface WebFetchParams {
  url: string;
  format: WebFetchFormat;
  timeoutSeconds?: number;
  maxCharacters: number;
}

export interface TimeoutSignalFactoryInput {
  timeoutMs: number;
  parent?: AbortSignal;
}

export interface TimeoutSignalHandle {
  signal: AbortSignal;
  clear: () => void;
}

export interface WebFetchResult {
  originalUrl: string;
  finalUrl: string;
  status: number;
  contentType: string;
  mime: string;
  format: WebFetchFormat;
  title: string | null;
  bytes: number;
  maxCharacters: number;
  truncated: boolean;
  content: string;
  binary: boolean;
}

export interface WebFetchOptions {
  fetchImpl?: typeof fetch;
  resolveHostname?: (hostname: string) => Promise<string[]>;
  allowPrivateNetwork?: boolean;
  createTimeoutSignal?: (input: TimeoutSignalFactoryInput) => TimeoutSignalHandle;
}

const MAX_RESPONSE_BYTES = 5 * 1024 * 1024;
const DEFAULT_TIMEOUT_MS = 30_000;
const MAX_TIMEOUT_MS = 120_000;
const MAX_REDIRECTS = 5;
const HONEST_USER_AGENT = "pi-coding-agent web_fetch";

export async function fetchWebUrl(
  params: WebFetchParams,
  signal?: AbortSignal,
  options: WebFetchOptions = {},
): Promise<WebFetchResult> {
  if (params.maxCharacters < 1) throw new Error("web_fetch maxCharacters must be at least 1.");

  const originalUrl = await validatePublicWebUrl(params.url, options);
  const timeoutMs = Math.min(Math.round((params.timeoutSeconds ?? DEFAULT_TIMEOUT_MS / 1000) * 1000), MAX_TIMEOUT_MS);
  if (timeoutMs < 1) throw new Error("web_fetch timeout must be at least 1 second.");

  const { signal: requestSignal, clear } = (options.createTimeoutSignal ?? createTimeoutSignal)({ timeoutMs, parent: signal });
  try {
    const { response, finalUrl } = await fetchWithRedirects(originalUrl, params.format, requestSignal, options);

    if (!response.ok) {
      throw new Error(`Request failed with status code: ${response.status}`);
    }

    const contentLength = response.headers.get("content-length");
    if (contentLength != null && Number.parseInt(contentLength, 10) > MAX_RESPONSE_BYTES) {
      throw new Error("Response too large (exceeds 5MB limit).");
    }

    const arrayBuffer = await response.arrayBuffer();
    if (arrayBuffer.byteLength > MAX_RESPONSE_BYTES) {
      throw new Error("Response too large (exceeds 5MB limit).");
    }

    const contentType = response.headers.get("content-type") ?? "";
    const mime = getMime(contentType);
    const binary = isBinaryMime(mime);

    if (binary) {
      return {
        originalUrl: originalUrl.toString(),
        finalUrl,
        status: response.status,
        contentType,
        mime,
        format: params.format,
        title: null,
        bytes: arrayBuffer.byteLength,
        maxCharacters: params.maxCharacters,
        truncated: false,
        content: `Binary response omitted (${mime || "unknown content type"}, ${arrayBuffer.byteLength} bytes).`,
        binary: true,
      };
    }

    const rawContent = new TextDecoder().decode(arrayBuffer);
    const title = mime === "text/html" || mime === "application/xhtml+xml" ? extractHtmlTitle(rawContent) : null;
    const formatted = formatFetchedContent(rawContent, mime, params.format, finalUrl);
    const truncated = formatted.length > params.maxCharacters;

    return {
      originalUrl: originalUrl.toString(),
      finalUrl,
      status: response.status,
      contentType,
      mime,
      format: params.format,
      title,
      bytes: arrayBuffer.byteLength,
      maxCharacters: params.maxCharacters,
      truncated,
      content: truncated ? formatted.slice(0, params.maxCharacters) : formatted,
      binary: false,
    };
  } finally {
    clear();
  }
}

export async function validatePublicWebUrl(url: string, options: WebFetchOptions = {}): Promise<URL> {
  const trimmed = url.trim();
  if (!trimmed) throw new Error("web_fetch requires a non-empty URL.");

  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch (error) {
    throw new Error(`Invalid URL: ${error instanceof Error ? error.message : String(error)}`);
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error("URL must start with http:// or https://.");
  }

  if (parsed.username || parsed.password) {
    throw new Error("URLs with embedded credentials are not allowed.");
  }

  if (!options.allowPrivateNetwork) {
    const hostname = normalizeHostname(parsed.hostname);
    if (isLocalHostname(hostname)) throw new Error("Localhost URLs are not allowed.");
    if (isPrivateOrReservedAddress(hostname)) throw new Error("Private, local, or reserved IP addresses are not allowed.");

    const addresses = await resolveHostname(hostname, options.resolveHostname);
    for (const address of addresses) {
      if (isPrivateOrReservedAddress(normalizeHostname(address))) {
        throw new Error("URL resolves to a private, local, or reserved IP address.");
      }
    }
  }

  return parsed;
}

export function extractHtmlTitle(html: string): string | null {
  const match = html.match(/<title\b[^>]*>([\s\S]*?)<\/title>/i);
  const title = match?.[1] == null ? "" : normalizeText(decodeHtml(stripTags(match[1])));
  return title || null;
}

export function formatFetchedContent(content: string, mime: string, format: WebFetchFormat, baseUrl: string): string {
  const isHtml = mime === "text/html" || mime === "application/xhtml+xml";

  if (format === "html") return content;
  if (!isHtml) return content.trim();
  if (format === "text") return htmlToText(content);
  return htmlToMarkdown(content, baseUrl);
}

function getAcceptHeader(format: WebFetchFormat): string {
  switch (format) {
    case "markdown":
      return "text/markdown;q=1.0, text/x-markdown;q=0.9, text/plain;q=0.8, text/html;q=0.7, */*;q=0.1";
    case "text":
      return "text/plain;q=1.0, text/markdown;q=0.9, text/html;q=0.8, */*;q=0.1";
    case "html":
      return "text/html;q=1.0, application/xhtml+xml;q=0.9, text/plain;q=0.8, text/markdown;q=0.7, */*;q=0.1";
  }
}

async function fetchWithRedirects(
  initialUrl: URL,
  format: WebFetchFormat,
  signal: AbortSignal,
  options: WebFetchOptions,
): Promise<{ response: Response; finalUrl: string }> {
  const fetchImpl = options.fetchImpl ?? fetch;
  let currentUrl = initialUrl;

  for (let redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount++) {
    const response = await fetchImpl(currentUrl, {
      method: "GET",
      redirect: "manual",
      signal,
      headers: {
        "User-Agent": HONEST_USER_AGENT,
        Accept: getAcceptHeader(format),
        "Accept-Language": "en-US,en;q=0.9",
      },
    });

    if (!isRedirect(response.status)) return { response, finalUrl: response.url || currentUrl.toString() };

    const location = response.headers.get("location");
    if (!location) throw new Error(`Redirect response ${response.status} did not include a Location header.`);
    if (redirectCount === MAX_REDIRECTS) throw new Error(`Too many redirects (>${MAX_REDIRECTS}).`);

    currentUrl = await validatePublicWebUrl(new URL(location, currentUrl).toString(), options);
  }

  throw new Error(`Too many redirects (>${MAX_REDIRECTS}).`);
}

function isRedirect(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

async function resolveHostname(hostname: string, customResolver?: (hostname: string) => Promise<string[]>): Promise<string[]> {
  if (getIpVersion(hostname)) return [hostname];
  if (customResolver) return customResolver(hostname);

  // @ts-expect-error Node builtins are provided by the pi runtime; this extension does not vendor @types/node.
  const { lookup } = (await import("node:dns/promises")) as {
    lookup: (hostname: string, options: { all: true; verbatim: true }) => Promise<Array<{ address: string }>>;
  };
  const records = await lookup(hostname, { all: true, verbatim: true });
  return records.map((record) => record.address);
}

function normalizeHostname(hostname: string): string {
  const normalized = hostname.trim().toLowerCase();
  return normalized.startsWith("[") && normalized.endsWith("]") ? normalized.slice(1, -1) : normalized;
}

function isLocalHostname(hostname: string): boolean {
  return hostname === "localhost" || hostname.endsWith(".localhost");
}

function getIpVersion(address: string): 0 | 4 | 6 {
  if (isIpv4Address(address)) return 4;
  if (/^[0-9a-f:.]+$/i.test(address) && address.includes(":")) return 6;
  return 0;
}

function isIpv4Address(address: string): boolean {
  const parts = address.split(".");
  return parts.length === 4 && parts.every((part) => /^\d{1,3}$/.test(part) && Number.parseInt(part, 10) >= 0 && Number.parseInt(part, 10) <= 255);
}

function isPrivateOrReservedAddress(address: string): boolean {
  const ipVersion = getIpVersion(address);
  if (ipVersion === 4) return isPrivateOrReservedIpv4(address);
  if (ipVersion === 6) return isPrivateOrReservedIpv6(address);
  return false;
}

function isPrivateOrReservedIpv4(address: string): boolean {
  const parts = address.split(".").map((part) => Number.parseInt(part, 10));
  if (parts.length !== 4 || parts.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) return true;

  const [a, b] = parts;
  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 198 && (b === 18 || b === 19)) ||
    a >= 224
  );
}

function isPrivateOrReservedIpv6(address: string): boolean {
  const normalized = address.toLowerCase();
  if (normalized === "::" || normalized === "::1") return true;

  const mappedIpv4 = normalized.match(/::ffff:(\d+\.\d+\.\d+\.\d+)$/i)?.[1];
  if (mappedIpv4) return isPrivateOrReservedIpv4(mappedIpv4);

  const firstHextet = Number.parseInt(normalized.split(":")[0] || "0", 16);
  if (!Number.isFinite(firstHextet)) return true;

  return (firstHextet & 0xfe00) === 0xfc00 || (firstHextet & 0xffc0) === 0xfe80 || (firstHextet & 0xff00) === 0xff00;
}

function isBinaryMime(mime: string): boolean {
  if (!mime) return false;
  if (mime === "image/svg+xml") return false;
  if (mime.startsWith("text/")) return false;
  if (
    mime === "application/json" ||
    mime === "application/xml" ||
    mime === "application/xhtml+xml" ||
    mime === "application/javascript" ||
    mime.endsWith("+json") ||
    mime.endsWith("+xml")
  ) {
    return false;
  }
  return mime.startsWith("image/") || mime.startsWith("audio/") || mime.startsWith("video/") || mime === "application/octet-stream";
}

function getMime(contentType: string): string {
  return contentType.split(";")[0]?.trim().toLowerCase() ?? "";
}

function htmlToText(html: string): string {
  const withoutUnsafe = removeUnsafeHtml(html);
  const withBreaks = withoutUnsafe
    .replace(/<br\s*\/?\s*>/gi, "\n")
    .replace(/<\/p\s*>/gi, "\n\n")
    .replace(/<\/div\s*>/gi, "\n")
    .replace(/<\/h[1-6]\s*>/gi, "\n\n")
    .replace(/<li\b[^>]*>/gi, "\n- ")
    .replace(/<\/(li|ul|ol|section|article|header|footer|nav|main)\s*>/gi, "\n");

  return normalizeText(decodeHtml(stripTags(withBreaks)));
}

function htmlToMarkdown(html: string, baseUrl: string): string {
  let markdown = removeUnsafeHtml(html);

  markdown = markdown.replace(/<pre\b[^>]*><code\b[^>]*>([\s\S]*?)<\/code><\/pre>/gi, (_, code) => {
    return `\n\n\`\`\`\n${decodeHtml(code).trim()}\n\`\`\`\n\n`;
  });
  markdown = markdown.replace(/<pre\b[^>]*>([\s\S]*?)<\/pre>/gi, (_, code) => {
    return `\n\n\`\`\`\n${decodeHtml(stripTags(code)).trim()}\n\`\`\`\n\n`;
  });
  markdown = markdown.replace(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi, (_, level, text) => {
    return `\n\n${"#".repeat(Number(level))} ${normalizeInline(stripTags(text))}\n\n`;
  });
  markdown = markdown.replace(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi, (_, attrs, text) => {
    const label = normalizeInline(stripTags(text));
    const href = extractHref(attrs, baseUrl);
    return label && href ? `[${label}](${href})` : label;
  });
  markdown = markdown
    .replace(/<br\s*\/?\s*>/gi, "\n")
    .replace(/<li\b[^>]*>/gi, "\n- ")
    .replace(/<\/(p|div|li|ul|ol|section|article|header|footer|nav|main|blockquote)\s*>/gi, "\n\n");

  return normalizeMarkdown(decodeHtml(stripTags(markdown)));
}

function removeUnsafeHtml(html: string): string {
  return html
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<head\b[\s\S]*?<\/head>/gi, "")
    .replace(/<script\b[\s\S]*?<\/script>/gi, "")
    .replace(/<style\b[\s\S]*?<\/style>/gi, "")
    .replace(/<noscript\b[\s\S]*?<\/noscript>/gi, "")
    .replace(/<iframe\b[\s\S]*?<\/iframe>/gi, "")
    .replace(/<object\b[\s\S]*?<\/object>/gi, "")
    .replace(/<embed\b[\s\S]*?>/gi, "");
}

function extractHref(attrs: string, baseUrl: string): string {
  const match = attrs.match(/\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
  const href = match?.[1] ?? match?.[2] ?? match?.[3] ?? "";
  if (!href || href.startsWith("#") || /^javascript:/i.test(href)) return "";

  try {
    const parsed = new URL(decodeHtml(href), baseUrl);
    return parsed.protocol === "http:" || parsed.protocol === "https:" ? parsed.toString() : "";
  } catch {
    return "";
  }
}

function stripTags(text: string): string {
  return text.replace(/<[^>]*>/g, "");
}

function normalizeInline(text: string): string {
  return normalizeText(decodeHtml(text)).replace(/\n+/g, " ");
}

function normalizeText(text: string): string {
  return text
    .replace(/\r\n?/g, "\n")
    .replace(/[ \t]+/g, " ")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function normalizeMarkdown(text: string): string {
  return normalizeText(text).replace(/\n{3,}/g, "\n\n");
}

function decodeHtml(text: string): string {
  const named: Record<string, string> = {
    amp: "&",
    apos: "'",
    gt: ">",
    lt: "<",
    nbsp: " ",
    quot: '"',
  };

  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (entity, body: string) => {
    const lower = body.toLowerCase();
    if (lower.startsWith("#x")) return safeCodePoint(Number.parseInt(lower.slice(2), 16), entity);
    if (lower.startsWith("#")) return safeCodePoint(Number.parseInt(lower.slice(1), 10), entity);
    return named[lower] ?? entity;
  });
}

function safeCodePoint(codePoint: number, fallback: string): string {
  return Number.isFinite(codePoint) ? String.fromCodePoint(codePoint) : fallback;
}

function createTimeoutSignal({ timeoutMs, parent }: TimeoutSignalFactoryInput): TimeoutSignalHandle {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(new Error(`web_fetch timed out after ${timeoutMs}ms.`)), timeoutMs);
  const abortFromParent = () => controller.abort(parent?.reason ?? new Error("web_fetch cancelled."));

  if (parent?.aborted) abortFromParent();
  else parent?.addEventListener("abort", abortFromParent, { once: true });

  return {
    signal: controller.signal,
    clear: () => {
      clearTimeout(timeout);
      parent?.removeEventListener("abort", abortFromParent);
    },
  };
}
