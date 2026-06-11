export type PiApi = "openai-completions" | "openai-responses" | "anthropic-messages";

export interface PiProviderModelConfig {
  id: string;
  name: string;
  api?: PiApi;
  reasoning: boolean;
  thinkingLevelMap?: Partial<Record<"off" | "minimal" | "low" | "medium" | "high" | "xhigh", string | null>>;
  input: ("text" | "image")[];
  cost: {
    input: number;
    output: number;
    cacheRead: number;
    cacheWrite: number;
  };
  contextWindow: number;
  maxTokens: number;
  compat?: Record<string, unknown>;
}

export interface PiProviderConfig {
  name?: string;
  baseUrl?: string;
  api?: PiApi;
  apiKey?: string;
  headers?: Record<string, string>;
  models?: PiProviderModelConfig[];
}

export interface PiModelsJson {
  providers?: Record<string, PiProviderConfig>;
}

export interface CopilotOAuthCredentials {
  type?: string;
  refresh?: string;
  access?: string;
  expires?: number;
  enterpriseUrl?: string;
}

export interface CopilotAuthFile {
  "github-copilot"?: CopilotOAuthCredentials;
}

export interface CopilotTokenInfo {
  token: string;
  apiBaseUrl: string;
  expires?: number;
}

export interface CopilotTokenResponse {
  token?: string;
  expires_at?: number;
  endpoints?: {
    api?: string;
  };
}

export interface CopilotLiveModelsResponse {
  data?: CopilotLiveModel[];
}

export interface CopilotLiveModel {
  id?: string;
  name?: string;
  vendor?: string;
  version?: string;
  model_picker_enabled?: boolean;
  supported_endpoints?: string[];
  policy?: {
    state?: string;
  };
  billing?: {
    token_prices?: CopilotTokenPrices;
  };
  capabilities?: {
    family?: string;
    type?: string;
    limits?: {
      max_context_window_tokens?: number;
      max_prompt_tokens?: number;
      max_output_tokens?: number;
      vision?: unknown;
    };
    supports?: {
      vision?: boolean;
      adaptive_thinking?: boolean;
      reasoning_effort?: string[];
      [key: string]: unknown;
    };
  };
}

export interface CopilotTokenPrices {
  batch_size?: number;
  default?: CopilotTokenPriceTier;
  long_context?: CopilotTokenPriceTier;
}

export interface CopilotTokenPriceTier {
  input_price?: number;
  output_price?: number;
  cache_price?: number;
  context_max?: number;
}

export interface CopilotLiveModelsProviderDeps {
  fetchImpl: typeof fetch;
  readTextFile(path: string): Promise<string>;
  writeDebug?(message: string): void;
  now(): number;
}

export interface CopilotModelsJsonWriterDeps extends CopilotLiveModelsProviderDeps {
  ensureDir(path: string): Promise<void>;
  writeTextFile(path: string, text: string): Promise<void>;
}

export interface DiscoverOptions {
  agentDir: string;
  contextReserveTokens: number;
}
