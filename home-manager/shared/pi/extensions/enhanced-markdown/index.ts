import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import {
  Markdown,
  truncateToWidth,
  visibleWidth,
  wrapTextWithAnsi,
} from "@mariozechner/pi-tui";
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

type RenderToken = (
  this: MarkdownInstance,
  token: MarkdownToken,
  width: number,
  nextTokenType?: string,
  styleContext?: unknown,
) => string[];

const PATCH_MARKER = Symbol.for("pi.enhanced-markdown.patch-applied");

export function patchMarkdownCodeBlocks() {
  const prototype = Markdown.prototype as unknown as {
    [PATCH_MARKER]?: boolean;
    renderToken: RenderToken;
  };

  if (prototype[PATCH_MARKER]) return;

  const originalRenderToken = prototype.renderToken;
  prototype.renderToken = function renderTokenWithEnhancedCodeBlocks(
    token,
    width,
    nextTokenType,
    styleContext,
  ) {
    if (token.type === "code") {
      return renderCodeBlockLines(this.theme, token, width, nextTokenType, {
        truncateToWidth,
        visibleWidth,
        wrapTextWithAnsi,
      });
    }

    return originalRenderToken.call(
      this,
      token,
      width,
      nextTokenType,
      styleContext,
    );
  };

  prototype[PATCH_MARKER] = true;
}

export default function enhancedMarkdownExtension(_pi: ExtensionAPI) {
  patchMarkdownCodeBlocks();
}
