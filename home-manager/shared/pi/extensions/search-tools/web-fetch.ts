import http from "node:http";
import https from "node:https";
import { isIP } from "node:net";
import { Readable } from "node:stream";
import { isLocalHostname, isPublicIpAddress, normalizeHostname } from "./network-safety.ts";

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
  fullContent?: string;
  binary: boolean;
}

export interface WebFetchOptions {
  fetchImpl?: typeof fetch;
  requestImpl?: (
    url: URL,
    address: string,
    family: 4 | 6,
    init: { signal: AbortSignal; headers: Record<string, string> },
  ) => Promise<Response>;
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

  const timeoutMs = Math.min(Math.round((params.timeoutSeconds ?? DEFAULT_TIMEOUT_MS / 1000) * 1000), MAX_TIMEOUT_MS);
  if (timeoutMs < 1) throw new Error("web_fetch timeout must be at least 1 second.");

  const { signal: requestSignal, clear } = (options.createTimeoutSignal ?? createTimeoutSignal)({ timeoutMs, parent: signal });
  try {
    const originalUrl = await validatePublicWebUrl(params.url, options, requestSignal);
    const { response, finalUrl } = await fetchWithRedirects(originalUrl, params.format, requestSignal, options);

    if (!response.ok) {
      throw new Error(`Request failed with status code: ${response.status}`);
    }

    const contentEncoding = response.headers.get("content-encoding")?.trim().toLowerCase();
    if (contentEncoding && contentEncoding !== "identity") {
      throw new Error(`Unsupported response content encoding: ${contentEncoding}.`);
    }

    const contentLength = response.headers.get("content-length");
    if (contentLength != null && /^\d+$/u.test(contentLength) && Number(contentLength) > MAX_RESPONSE_BYTES) {
      throw new Error("Response too large (exceeds 5MB limit).");
    }

    const body = await readResponseBodyLimited(response, requestSignal);

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
        bytes: body.byteLength,
        maxCharacters: params.maxCharacters,
        truncated: false,
        content: `Binary response omitted (${mime || "unknown content type"}, ${body.byteLength} bytes).`,
        binary: true,
      };
    }

    const rawContent = sanitizeControls(new TextDecoder().decode(body));
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
      bytes: body.byteLength,
      maxCharacters: params.maxCharacters,
      truncated,
      content: truncated ? formatted.slice(0, params.maxCharacters) : formatted,
      fullContent: truncated ? formatted : undefined,
      binary: false,
    };
  } finally {
    clear();
  }
}

export async function readResponseBodyLimited(response: Response, signal?: AbortSignal): Promise<Uint8Array> {
  if (!response.body) return new Uint8Array();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  try {
    while (true) {
      signal?.throwIfAborted();
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      totalBytes += value.byteLength;
      if (totalBytes > MAX_RESPONSE_BYTES) {
        await reader.cancel("Response exceeded 5MB limit.");
        throw new Error("Response too large (exceeds 5MB limit).");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const output = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

async function raceWithAbort<T>(promise: Promise<T>, signal?: AbortSignal): Promise<T> {
  if (!signal) return promise;
  signal.throwIfAborted();
  return new Promise<T>((resolve, reject) => {
    const abort = () => reject(signal.reason ?? new Error("web_fetch cancelled."));
    signal.addEventListener("abort", abort, { once: true });
    promise.then(resolve, reject).finally(() => signal.removeEventListener("abort", abort));
  });
}

export async function validatePublicWebUrl(
  url: string,
  options: WebFetchOptions = {},
  signal?: AbortSignal,
): Promise<URL> {
  signal?.throwIfAborted();
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
    if (isIP(hostname) && !isPublicIpAddress(hostname)) throw new Error("Private, local, or reserved IP addresses are not allowed.");

    const addresses = await raceWithAbort(resolveHostname(hostname, options.resolveHostname), signal);
    if (addresses.length === 0) throw new Error("URL hostname did not resolve to an address.");
    for (const address of addresses) {
      if (!isPublicIpAddress(normalizeHostname(address))) {
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

export async function requestPinnedAddress(
  url: URL,
  address: string,
  family: 4 | 6,
  init: { signal: AbortSignal; headers: Record<string, string> },
  requestClient?: Pick<typeof http, "request">,
): Promise<Response> {
  const client = requestClient ?? (url.protocol === "https:" ? https : http);
  return new Promise((resolve, reject) => {
    const request = client.request(url, {
      method: "GET",
      headers: init.headers,
      signal: init.signal,
      family,
      autoSelectFamily: false,
      servername: url.protocol === "https:" && !isIP(url.hostname) ? url.hostname : undefined,
      lookup: (_hostname, lookupOptions, callback) => {
        if (typeof lookupOptions === "object" && lookupOptions.all) {
          callback(null, [{ address, family }]);
        } else {
          callback(null, address, family);
        }
      },
    }, (incoming) => {
      const headers = new Headers();
      for (let index = 0; index < incoming.rawHeaders.length; index += 2) {
        headers.append(incoming.rawHeaders[index]!, incoming.rawHeaders[index + 1]!);
      }
      const status = incoming.statusCode ?? 0;
      const body = status === 204 || status === 205 || status === 304
        ? null
        : Readable.toWeb(incoming) as ReadableStream;
      resolve(new Response(body, { status, statusText: incoming.statusMessage, headers }));
    });
    // Keep consuming transport errors after the promise settles. ClientRequest can
    // emit more than one error during abort/connect races, and a once-listener
    // would leave a later socket error unhandled and terminate Pi.
    request.on("error", reject);
    request.end();
  });
}

async function fetchWithRedirects(
  initialUrl: URL,
  format: WebFetchFormat,
  signal: AbortSignal,
  options: WebFetchOptions,
): Promise<{ response: Response; finalUrl: string }> {
  let currentUrl = initialUrl;

  for (let redirectCount = 0; redirectCount <= MAX_REDIRECTS; redirectCount++) {
    signal.throwIfAborted();
    const headers = {
      "User-Agent": HONEST_USER_AGENT,
      Accept: getAcceptHeader(format),
      "Accept-Language": "en-US,en;q=0.9",
      "Accept-Encoding": "identity",
    };
    let response: Response;
    if (options.fetchImpl) {
      response = await options.fetchImpl(currentUrl, {
        method: "GET",
        redirect: "manual",
        signal,
        headers,
      });
    } else {
      const hostname = normalizeHostname(currentUrl.hostname);
      const addresses = await raceWithAbort(resolveHostname(hostname, options.resolveHostname), signal);
      if (addresses.length === 0 || addresses.some((address) => !isPublicIpAddress(normalizeHostname(address)))) {
        throw new Error("URL resolves to a private, local, or reserved IP address.");
      }
      const address = normalizeHostname(addresses[0]!);
      const family = isIP(address);
      if (family !== 4 && family !== 6) throw new Error("URL resolved to an invalid IP address.");
      response = await (options.requestImpl ?? requestPinnedAddress)(currentUrl, address, family, { signal, headers });
    }

    if (!isRedirect(response.status)) return { response, finalUrl: response.url || currentUrl.toString() };

    const location = response.headers.get("location");
    await response.body?.cancel();
    if (!location) throw new Error(`Redirect response ${response.status} did not include a Location header.`);
    if (redirectCount === MAX_REDIRECTS) throw new Error(`Too many redirects (>${MAX_REDIRECTS}).`);

    currentUrl = await validatePublicWebUrl(new URL(location, currentUrl).toString(), options, signal);
  }

  throw new Error(`Too many redirects (>${MAX_REDIRECTS}).`);
}

function isRedirect(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
}

async function resolveHostname(hostname: string, customResolver?: (hostname: string) => Promise<string[]>): Promise<string[]> {
  if (isIP(hostname)) return [hostname];
  if (customResolver) return customResolver(hostname);

  // @ts-expect-error Node builtins are provided by the pi runtime; this extension does not vendor @types/node.
  const { lookup } = (await import("node:dns/promises")) as {
    lookup: (hostname: string, options: { all: true; verbatim: true }) => Promise<Array<{ address: string }>>;
  };
  const records = await lookup(hostname, { all: true, verbatim: true });
  return records.map((record) => record.address);
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

function sanitizeControls(text: string): string {
  return text.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]/gu, "\uFFFD");
}

function normalizeText(text: string): string {
  return sanitizeControls(text)
    .replace(/\r\n?/g, "\n")
    .replace(/[ \t]+/g, " ")
    .replace(/\n[ \t]+/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function normalizeMarkdown(text: string): string {
  return normalizeText(text)
    .replace(/[<>]/gu, (character) => `\\${character}`)
    .replace(/\n{3,}/g, "\n\n");
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

function safeCodePoint(codePoint: number, _fallback: string): string {
  const invalidControl =
    (codePoint >= 0 && codePoint <= 8)
    || (codePoint >= 11 && codePoint <= 12)
    || (codePoint >= 14 && codePoint <= 31)
    || (codePoint >= 0x7f && codePoint <= 0x9f);
  if (
    !Number.isInteger(codePoint)
    || codePoint < 1
    || codePoint > 0x10ffff
    || (codePoint >= 0xd800 && codePoint <= 0xdfff)
    || invalidControl
  ) {
    return "\uFFFD";
  }
  return String.fromCodePoint(codePoint);
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
