import path from "node:path";
import { COPILOT_HEADERS } from "./constants.ts";
import type { CopilotAuthFile, CopilotOAuthCredentials, CopilotTokenInfo, CopilotTokenResponse } from "./types.ts";

export function normalizeEnterpriseDomain(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  if (!trimmed) return undefined;

  try {
    const url = trimmed.includes("://") ? new URL(trimmed) : new URL(`https://${trimmed}`);
    return url.hostname;
  } catch {
    return undefined;
  }
}

export function getCopilotTokenUrl(enterpriseUrl: string | undefined): string {
  const domain = normalizeEnterpriseDomain(enterpriseUrl) ?? "github.com";
  return `https://api.${domain}/copilot_internal/v2/token`;
}

export function getApiBaseUrlFromCopilotToken(token: string | undefined): string | undefined {
  if (!token) return undefined;
  const match = token.match(/(?:^|;)proxy-ep=([^;]+)/);
  if (!match?.[1]) return undefined;

  const apiHost = match[1].replace(/^proxy\./, "api.");
  return `https://${apiHost}`;
}

export function parseAuthFile(text: string): CopilotOAuthCredentials | undefined {
  const parsed = JSON.parse(text) as CopilotAuthFile;
  const credentials = parsed["github-copilot"];
  if (credentials?.type !== "oauth") return undefined;
  return credentials;
}

export function authJsonPath(agentDir: string): string {
  return path.join(agentDir, "auth.json");
}

export async function loadCopilotCredentials(
  agentDir: string,
  readTextFile: (path: string) => Promise<string>,
): Promise<CopilotOAuthCredentials | undefined> {
  try {
    return parseAuthFile(await readTextFile(authJsonPath(agentDir)));
  } catch {
    return undefined;
  }
}

export function normalizeExpiresMs(expires: number | undefined): number | undefined {
  if (expires === undefined) return undefined;
  // Pi currently stores OAuth expiry in epoch milliseconds, while GitHub's
  // Copilot token endpoint returns epoch seconds. Accept either to keep this
  // helper robust across upstream schema changes.
  return expires < 10_000_000_000 ? expires * 1000 : expires;
}

export function getValidCachedToken(
  credentials: CopilotOAuthCredentials | undefined,
  now: number,
): CopilotTokenInfo | undefined {
  if (!credentials?.access) return undefined;

  const expires = normalizeExpiresMs(credentials.expires);
  if (expires !== undefined && expires <= now + 60_000) return undefined;

  const apiBaseUrl = getApiBaseUrlFromCopilotToken(credentials.access);
  if (!apiBaseUrl) return undefined;

  return {
    token: credentials.access,
    apiBaseUrl,
    expires,
  };
}

export async function refreshCopilotToken(
  credentials: CopilotOAuthCredentials,
  fetchImpl: typeof fetch,
): Promise<CopilotTokenInfo | undefined> {
  if (!credentials.refresh) return undefined;

  const response = await fetchImpl(getCopilotTokenUrl(credentials.enterpriseUrl), {
    headers: {
      ...COPILOT_HEADERS,
      Accept: "application/json",
      Authorization: `Bearer ${credentials.refresh}`,
    },
  });

  if (!response.ok) {
    throw new Error(`GitHub Copilot token refresh failed: ${response.status} ${response.statusText}`);
  }

  const payload = (await response.json()) as CopilotTokenResponse;
  if (!payload.token) return undefined;

  const apiBaseUrl = payload.endpoints?.api ?? getApiBaseUrlFromCopilotToken(payload.token);
  if (!apiBaseUrl) return undefined;

  return {
    token: payload.token,
    apiBaseUrl,
    expires: payload.expires_at ? payload.expires_at * 1000 : undefined,
  };
}

export async function resolveCopilotToken(
  credentials: CopilotOAuthCredentials | undefined,
  fetchImpl: typeof fetch,
  now: number,
): Promise<CopilotTokenInfo | undefined> {
  const cached = getValidCachedToken(credentials, now);
  if (cached) return cached;
  if (!credentials) return undefined;
  return refreshCopilotToken(credentials, fetchImpl);
}
