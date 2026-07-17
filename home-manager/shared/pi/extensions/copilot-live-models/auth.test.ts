import assert from "node:assert/strict";
import test from "node:test";
import {
  getApiBaseUrlFromCopilotCredential,
  getApiBaseUrlFromCopilotToken,
} from "./auth.ts";

const ACCESS_TOKEN = "tid=abc;proxy-ep=proxy.enterprise.githubcopilot.com;exp=999";

test("getApiBaseUrlFromCopilotToken converts proxy endpoint to API endpoint", () => {
  assert.equal(getApiBaseUrlFromCopilotToken(ACCESS_TOKEN), "https://api.enterprise.githubcopilot.com");
});

test("getApiBaseUrlFromCopilotToken rejects tokens without endpoint metadata", () => {
  assert.equal(getApiBaseUrlFromCopilotToken(undefined), undefined);
  assert.equal(getApiBaseUrlFromCopilotToken("plain-token"), undefined);
});

test("getApiBaseUrlFromCopilotCredential prefers explicit endpoint metadata", () => {
  assert.equal(
    getApiBaseUrlFromCopilotCredential({
      access: ACCESS_TOKEN,
      endpoints: { api: "https://api.explicit.githubcopilot.com/" },
    }),
    "https://api.explicit.githubcopilot.com",
  );
});

test("getApiBaseUrlFromCopilotCredential follows Pi's enterprise and individual fallbacks", () => {
  assert.equal(
    getApiBaseUrlFromCopilotCredential({ access: "plain-token", enterpriseUrl: "https://example.ghe.com" }),
    "https://copilot-api.example.ghe.com",
  );
  assert.equal(
    getApiBaseUrlFromCopilotCredential({ access: "plain-token" }),
    "https://api.individual.githubcopilot.com",
  );
});
