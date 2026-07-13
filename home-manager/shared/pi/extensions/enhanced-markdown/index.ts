import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import {
  Markdown,
  truncateToWidth,
  visibleWidth,
  wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
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

const PATCH_VERSION = 3;
const PATCH_MARKER = Symbol.for("pi.enhanced-markdown.patch-version");
const ORIGINAL_RENDER_TOKEN = Symbol.for(
  "pi.enhanced-markdown.original-render-token",
);
const PATCH_STATE = Symbol.for("pi.enhanced-markdown.patch-state-v3");
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

type MarkdownPatchState = {
  original: RenderToken;
  installed: RenderToken;
  owners: Set<symbol>;
};

export function patchMarkdownCodeBlocks(owner = Symbol("enhanced-markdown-patch-owner")): () => void {
  const prototype = Markdown.prototype as unknown as {
    [ORIGINAL_RENDER_TOKEN]?: RenderToken;
    [PATCH_MARKER]?: number;
    [PATCH_STATE]?: MarkdownPatchState;
    renderToken: RenderToken;
  };

  let patchState = prototype[PATCH_STATE];
  if (!patchState) {
    if (prototype[PATCH_MARKER] === 2 && prototype[ORIGINAL_RENDER_TOKEN]) {
      prototype.renderToken = prototype[ORIGINAL_RENDER_TOKEN];
      delete prototype[PATCH_MARKER];
      delete prototype[ORIGINAL_RENDER_TOKEN];
    }

    const original = prototype.renderToken;
    const installed: RenderToken = function renderTokenWithEnhancedCodeBlocks(
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
          { truncateToWidth, visibleWidth, wrapTextWithAnsi },
          (code, lang) => highlightCodeWithOverrides(this.theme, code, lang),
        );
      }
      return original.call(this, token, width, nextTokenType, styleContext);
    };

    patchState = { original, installed, owners: new Set() };
    prototype.renderToken = installed;
    prototype[PATCH_MARKER] = PATCH_VERSION;
    prototype[ORIGINAL_RENDER_TOKEN] = original;
    prototype[PATCH_STATE] = patchState;
  }
  patchState.owners.add(owner);

  let released = false;
  return () => {
    if (released) return;
    released = true;
    const current = prototype[PATCH_STATE];
    if (!current) return;
    current.owners.delete(owner);
    if (current.owners.size > 0) return;
    if (prototype.renderToken === current.installed) prototype.renderToken = current.original;
    delete prototype[PATCH_STATE];
    delete prototype[PATCH_MARKER];
    delete prototype[ORIGINAL_RENDER_TOKEN];
  };
}

export default function enhancedMarkdownExtension(pi: ExtensionAPI) {
  const owner = Symbol("enhanced-markdown-extension-instance");
  let releasePatch: (() => void) | undefined;

  pi.on("session_start", (_event, ctx) => {
    releasePatch?.();
    releasePatch = patchMarkdownCodeBlocks(owner);
    const state = getState();
    state.activeContext = ctx;
    state.activeOwner = owner;
  });

  pi.on("session_shutdown", () => {
    const globalState = globalThis as typeof globalThis & {
      [STATE_KEY]?: EnhancedMarkdownState;
    };
    const state = globalState[STATE_KEY];
    if (state?.activeOwner === owner) {
      state.activeContext = undefined;
      state.activeOwner = undefined;
    }
    releasePatch?.();
    releasePatch = undefined;
    if (!state?.activeOwner) delete globalState[STATE_KEY];
  });
}
