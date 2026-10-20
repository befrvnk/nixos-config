export type SourcePreference = "selected" | "clipboard";
export type QuickAction = "paste" | "copy";

export type Preferences = {
  apiKey: string;
  model: string;
  source?: SourcePreference;
  action?: QuickAction;
  customInstructions?: string;
};

export type RewritePreset = {
  id: string;
  title: string;
  description: string;
  instruction: string;
  successTitle: string;
  keywords?: string[];
};

export type RewriteRequest = {
  title: string;
  instruction: string;
  sourceText: string;
};
