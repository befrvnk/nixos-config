import type { SupportedLanguage } from "./types.js";

export const ACTIONS = [
  "hover",
  "definition",
  "references",
  "diagnostics",
  "document_symbols",
  "workspace_symbols",
] as const;

export const LANGUAGES = ["typescript", "nix", "kotlin"] as const;

export const LANGUAGE_IDS: Record<SupportedLanguage, string> = {
  kotlin: "kotlin",
  nix: "nix",
  typescript: "typescript",
};

export const LANGUAGE_EXTENSIONS: Array<{ suffixes: string[]; language: SupportedLanguage }> = [
  { suffixes: [".ts", ".tsx", ".js", ".jsx", ".mts", ".cts"], language: "typescript" },
  { suffixes: [".nix"], language: "nix" },
  { suffixes: [".kt", ".kts"], language: "kotlin" },
];

export const ROOT_MARKERS: Record<SupportedLanguage, string[]> = {
  kotlin: ["settings.gradle.kts", "settings.gradle", "gradlew", "pom.xml", "build.gradle.kts", "build.gradle"],
  nix: ["devenv.lock", "devenv.nix", "devenv.yaml", "flake.nix", "default.nix", "shell.nix"],
  typescript: ["tsconfig.json", "tsconfig.base.json", "jsconfig.json", "package.json", "pnpm-workspace.yaml"],
};

export const SYMBOL_KINDS: Record<number, string> = {
  1: "File",
  2: "Module",
  3: "Namespace",
  4: "Package",
  5: "Class",
  6: "Method",
  7: "Property",
  8: "Field",
  9: "Constructor",
  10: "Enum",
  11: "Interface",
  12: "Function",
  13: "Variable",
  14: "Constant",
  15: "String",
  16: "Number",
  17: "Boolean",
  18: "Array",
  19: "Object",
  20: "Key",
  21: "Null",
  22: "EnumMember",
  23: "Struct",
  24: "Event",
  25: "Operator",
  26: "TypeParameter",
};

export const DIAGNOSTIC_SEVERITY: Record<number, string> = {
  1: "Error",
  2: "Warning",
  3: "Information",
  4: "Hint",
};
