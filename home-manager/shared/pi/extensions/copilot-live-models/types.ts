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

export interface CopilotOAuthCredentials {
  type?: string;
  access?: string;
  apiBaseUrl?: string;
  enterpriseUrl?: string;
  endpoints?: {
    api?: string;
  };
  [key: string]: unknown;
}

export interface CopilotRefreshModelsContext {
  credential?: CopilotOAuthCredentials;
  allowNetwork: boolean;
  signal?: AbortSignal;
}

export interface PiProviderConfig {
  headers?: Record<string, string>;
  refreshModels?(context: CopilotRefreshModelsContext): Promise<PiProviderModelConfig[]>;
}

export interface CopilotTokenInfo {
  token: string;
  apiBaseUrl: string;
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
}
