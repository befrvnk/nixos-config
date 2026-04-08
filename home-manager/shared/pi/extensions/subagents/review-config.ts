import { COPILOT_PROVIDER } from "./types.js";

export const DEFAULT_REVIEWERS = [
  {
    label: "Opus 4.6",
    model: `${COPILOT_PROVIDER}/claude-opus-4.6`,
    focus: "correctness, regressions, hidden bugs, and edge cases",
  },
  {
    label: "Gemini 3.1",
    model: `${COPILOT_PROVIDER}/gemini-3.1-pro-preview`,
    focus: "maintainability, clarity, test gaps, and surprising behavior",
  },
] as const;
