import fs from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
import test from "node:test";
import { defaultAgentDir, defaultDeps, refreshCopilotLiveModels } from "./index.ts";
import type { CopilotOAuthCredentials } from "./types.ts";

const runLiveSmoke = process.env.PI_COPILOT_LIVE_MODELS_LIVE_TEST === "1";

test("live Copilot catalog exposes GPT-5.5 long-context metadata", { skip: !runLiveSmoke }, async () => {
  const agentDir = defaultAgentDir();
  const auth = JSON.parse(await fs.readFile(path.join(agentDir, "auth.json"), "utf8")) as {
    "github-copilot"?: CopilotOAuthCredentials;
  };
  const models = await refreshCopilotLiveModels(
    { credential: auth["github-copilot"], allowNetwork: true },
    defaultDeps(),
    128_000,
  );

  const gpt55 = models.find((model) => model.id === "gpt-5.5");
  assert.ok(gpt55, "expected gpt-5.5 in the live Copilot catalog");
  assert.equal(gpt55.api, "openai-responses");
  assert.equal(gpt55.maxTokens, 128_000);
  assert.ok(
    gpt55.contextWindow >= 1_000_000,
    `expected GPT-5.5 long-context metadata, got ${gpt55.contextWindow}`,
  );
});
