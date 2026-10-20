import type { RewritePreset } from "./types.js";

export const presets: RewritePreset[] = [
  {
    id: "improve-writing",
    title: "Improve Writing",
    description: "Improve clarity, grammar, and flow while preserving meaning.",
    instruction:
      "Rewrite the text to improve grammar, clarity, conciseness, and flow. Preserve the original meaning and keep the tone broadly similar.",
    successTitle: "Improved writing",
    keywords: ["improve", "writing", "clarity", "grammar"],
  },
  {
    id: "fix-spelling-and-grammar",
    title: "Fix Spelling and Grammar",
    description: "Correct spelling, grammar, and punctuation with minimal wording changes.",
    instruction:
      "Fix spelling, grammar, and punctuation mistakes. Keep the original wording whenever possible and do not add commentary.",
    successTitle: "Fixed spelling and grammar",
    keywords: ["grammar", "spelling", "proofread"],
  },
  {
    id: "make-shorter",
    title: "Make Shorter",
    description: "Rewrite the text more concisely while keeping the core meaning.",
    instruction:
      "Rewrite the text to be shorter and more concise while preserving the original meaning and important details.",
    successTitle: "Shortened text",
    keywords: ["shorter", "concise", "summary"],
  },
  {
    id: "make-longer",
    title: "Make Longer",
    description: "Expand the text without changing its meaning.",
    instruction:
      "Rewrite the text to be a little longer and more polished without changing its meaning or adding unrelated information.",
    successTitle: "Expanded text",
    keywords: ["longer", "expand", "elaborate"],
  },
  {
    id: "professional-tone",
    title: "Professional Tone",
    description: "Make the text sound more professional and polished.",
    instruction:
      "Rewrite the text in a professional, polished tone. Keep it clear, natural, and not overly formal.",
    successTitle: "Applied professional tone",
    keywords: ["professional", "formal", "tone"],
  },
  {
    id: "friendly-tone",
    title: "Friendly Tone",
    description: "Make the text sound warmer and more approachable.",
    instruction:
      "Rewrite the text in a friendly, warm, approachable tone while preserving the original meaning.",
    successTitle: "Applied friendly tone",
    keywords: ["friendly", "warm", "tone"],
  },
];

export const presetById = Object.fromEntries(
  presets.map((preset) => [preset.id, preset]),
) as Record<string, RewritePreset>;
