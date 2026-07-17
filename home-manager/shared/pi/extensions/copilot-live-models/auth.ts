import type { CopilotOAuthCredentials } from "./types.ts";

function normalizeHttpsBaseUrl(value: unknown): string | undefined {
  if (typeof value !== "string" || value.trim() === "") return undefined;

  try {
    const url = new URL(value);
    if (url.protocol !== "https:") return undefined;
    return url.href.replace(/\/$/, "");
  } catch {
    return undefined;
  }
}

function normalizeEnterpriseDomain(value: unknown): string | undefined {
  if (typeof value !== "string" || value.trim() === "") return undefined;

  try {
    const input = value.includes("://") ? value : `https://${value}`;
    return new URL(input).hostname || undefined;
  } catch {
    return undefined;
  }
}

export function getApiBaseUrlFromCopilotToken(token: string | undefined): string | undefined {
  if (!token) return undefined;
  const match = token.match(/(?:^|;)proxy-ep=([^;]+)/);
  if (!match?.[1]) return undefined;

  const apiHost = match[1].replace(/^proxy\./, "api.");
  return `https://${apiHost}`;
}

export function getApiBaseUrlFromCopilotCredential(credentials: CopilotOAuthCredentials): string {
  const endpoints = credentials.endpoints as { api?: string } | undefined;
  const credentialEndpoint = normalizeHttpsBaseUrl(credentials.apiBaseUrl)
    ?? normalizeHttpsBaseUrl(endpoints?.api);
  if (credentialEndpoint) return credentialEndpoint;

  const tokenEndpoint = getApiBaseUrlFromCopilotToken(credentials.access);
  if (tokenEndpoint) return tokenEndpoint;

  const enterpriseDomain = normalizeEnterpriseDomain(credentials.enterpriseUrl);
  return enterpriseDomain
    ? `https://copilot-api.${enterpriseDomain}`
    : "https://api.individual.githubcopilot.com";
}
