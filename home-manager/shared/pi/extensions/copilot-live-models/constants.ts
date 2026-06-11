export const COPILOT_PROVIDER = "github-copilot";
export const COPILOT_API_VERSION = "2026-06-01";
export const COPILOT_INTEGRATION_ID = "vscode-chat";

export const COPILOT_HEADERS = {
  "User-Agent": "GitHubCopilotChat/0.35.0",
  "Editor-Version": "vscode/1.107.0",
  "Editor-Plugin-Version": "copilot-chat/0.35.0",
  "Copilot-Integration-Id": COPILOT_INTEGRATION_ID,
  "X-GitHub-Api-Version": COPILOT_API_VERSION,
} as const;

export const DEFAULT_CONTEXT_RESERVE_TOKENS = 128_000;
export const DEFAULT_FETCH_TIMEOUT_MS = 10_000;
