import type {
  ExtensionAPI,
  ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import {
  Markdown,
  truncateToWidth,
  visibleWidth,
  wrapTextWithAnsi,
} from "@mariozechner/pi-tui";
import { highlightKotlinCode } from "./kotlin-highlighter.ts";
import { renderCodeBlockLines } from "./render-code-block.ts";

type MarkdownToken = {
  type: string;
  lang?: string;
  text?: string;
  [key: string]: unknown;
};

type MarkdownInstance = {
  theme: {
    codeBlock: (text: string) => string;
    codeBlockBorder: (text: string) => string;
    highlightCode?: (code: string, lang?: string) => string[];
  };
};

type EnhancedMarkdownState = {
  activeContext?: ExtensionContext;
  activeOwner?: symbol;
};

type RenderToken = (
  this: MarkdownInstance,
  token: MarkdownToken,
  width: number,
  nextTokenType?: string,
  styleContext?: unknown,
) => string[];

const PATCH_VERSION = 2;
const PATCH_MARKER = Symbol.for("pi.enhanced-markdown.patch-version");
const ORIGINAL_RENDER_TOKEN = Symbol.for(
  "pi.enhanced-markdown.original-render-token",
);
const STATE_KEY = Symbol.for("pi.enhanced-markdown.state");

function getState(): EnhancedMarkdownState {
  const globalState = globalThis as typeof globalThis & {
    [STATE_KEY]?: EnhancedMarkdownState;
  };
  globalState[STATE_KEY] ??= {};
  return globalState[STATE_KEY];
}

function highlightCodeWithOverrides(
  theme: MarkdownInstance["theme"],
  code: string,
  lang?: string,
): string[] {
  if (lang === "kotlin") {
    const state = getState();
    const kotlinTheme = state.activeContext?.hasUI
      ? state.activeContext.ui.theme
      : undefined;
    if (kotlinTheme) return highlightKotlinCode(code, kotlinTheme);
  }

  return theme.highlightCode
    ? theme.highlightCode(code, lang)
    : code.split("\n").map((line) => theme.codeBlock(line));
}

export function patchMarkdownCodeBlocks() {
  const prototype = Markdown.prototype as unknown as {
    [ORIGINAL_RENDER_TOKEN]?: RenderToken;
    [PATCH_MARKER]?: number;
    renderToken: RenderToken;
  };

  if (prototype[PATCH_MARKER] === PATCH_VERSION) return;

  prototype[ORIGINAL_RENDER_TOKEN] ??= prototype.renderToken;
  const originalRenderToken = prototype[ORIGINAL_RENDER_TOKEN];
  prototype.renderToken = function renderTokenWithEnhancedCodeBlocks(
    token,
    width,
    nextTokenType,
    styleContext,
  ) {
    if (token.type === "code") {
      return renderCodeBlockLines(
        this.theme,
        token,
        width,
        nextTokenType,
        {
          truncateToWidth,
          visibleWidth,
          wrapTextWithAnsi,
        },
        (code, lang) => highlightCodeWithOverrides(this.theme, code, lang),
      );
    }

    return originalRenderToken.call(
      this,
      token,
      width,
      nextTokenType,
      styleContext,
    );
  };

  prototype[PATCH_MARKER] = PATCH_VERSION;
}

export default function enhancedMarkdownExtension(pi: ExtensionAPI) {
  const owner = Symbol("enhanced-markdown-extension-instance");

  pi.on("session_start", (_event, ctx) => {
    const state = getState();
    state.activeContext = ctx;
    state.activeOwner = owner;
  });

  pi.on("session_shutdown", () => {
    const state = getState();
    if (state.activeOwner !== owner) return;
    state.activeContext = undefined;
    state.activeOwner = undefined;
  });

  patchMarkdownCodeBlocks();
}
