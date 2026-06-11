import assert from "node:assert/strict";
import test from "node:test";
import {
  getApiBaseUrlFromCopilotToken,
  getCopilotTokenUrl,
  getValidCachedToken,
  parseAuthFile,
  refreshCopilotToken,
} from "./auth.ts";

const ACCESS_TOKEN = "tid=abc;proxy-ep=proxy.enterprise.githubcopilot.com;exp=999";

test("parseAuthFile extracts GitHub Copilot OAuth credentials", () => {
  const credentials = parseAuthFile(
    JSON.stringify({
      "github-copilot": {
        type: "oauth",
        refresh: "ghu_refresh",
        access: ACCESS_TOKEN,
        expires: 1234,
      },
    }),
  );

  assert.equal(credentials?.refresh, "ghu_refresh");
  assert.equal(credentials?.access, ACCESS_TOKEN);
});

test("getApiBaseUrlFromCopilotToken converts proxy endpoint to API endpoint", () => {
  assert.equal(getApiBaseUrlFromCopilotToken(ACCESS_TOKEN), "https://api.enterprise.githubcopilot.com");
});

test("getCopilotTokenUrl supports github.com and enterprise domains", () => {
  assert.equal(getCopilotTokenUrl(undefined), "https://api.github.com/copilot_internal/v2/token");
  assert.equal(getCopilotTokenUrl("https://example.ghe.com"), "https://api.example.ghe.com/copilot_internal/v2/token");
});

test("getValidCachedToken accepts non-expired tokens with a proxy endpoint", () => {
  const token = getValidCachedToken({ type: "oauth", access: ACCESS_TOKEN, expires: 100_000_000_000 }, 1_000);

  assert.deepEqual(token, {
    token: ACCESS_TOKEN,
    apiBaseUrl: "https://api.enterprise.githubcopilot.com",
    expires: 100_000_000_000,
  });
});

test("getValidCachedToken normalizes epoch-second expirations", () => {
  const token = getValidCachedToken({ type: "oauth", access: ACCESS_TOKEN, expires: 100_000 }, 1_000);

  assert.deepEqual(token, {
    token: ACCESS_TOKEN,
    apiBaseUrl: "https://api.enterprise.githubcopilot.com",
    expires: 100_000_000,
  });
});

test("getValidCachedToken rejects tokens close to expiration", () => {
  assert.equal(getValidCachedToken({ type: "oauth", access: ACCESS_TOKEN, expires: 60 }, 1_000), undefined);
});

test("refreshCopilotToken exchanges the GitHub token and prefers endpoint metadata", async () => {
  let observedUrl = "";
  let observedAuthorization = "";

  const token = await refreshCopilotToken(
    { type: "oauth", refresh: "ghu_refresh" },
    (async (url, init) => {
      observedUrl = String(url);
      observedAuthorization = String((init?.headers as Record<string, string>).Authorization);
      return new Response(
        JSON.stringify({
          token: ACCESS_TOKEN,
          expires_at: 123,
          endpoints: { api: "https://api.enterprise.githubcopilot.com" },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }) as typeof fetch,
  );

  assert.equal(observedUrl, "https://api.github.com/copilot_internal/v2/token");
  assert.equal(observedAuthorization, "Bearer ghu_refresh");
  assert.deepEqual(token, {
    token: ACCESS_TOKEN,
    apiBaseUrl: "https://api.enterprise.githubcopilot.com",
    expires: 123_000,
  });
});
