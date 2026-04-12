import {
  Action,
  ActionPanel,
  Detail,
  Icon,
  Toast,
  showToast,
} from "@vicinae/api";
import { useEffect, useState } from "react";
import { rewriteWithGemini } from "../lib/gemini.js";
import { handleOutput } from "../lib/actions.js";
import { getPreferences } from "../lib/preferences.js";
import { createDiffSummary } from "../lib/diff.js";
import type { RewriteRequest } from "../lib/types.js";

function buildMarkdown(sourceText: string, rewrittenText: string): string {
  const diff = createDiffSummary(sourceText, rewrittenText);
  return diff.html;
}

export function RewriteResultView({ request }: { request: RewriteRequest }) {
  const preferences = getPreferences();
  const [rewrittenText, setRewrittenText] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [refreshToken, setRefreshToken] = useState<number>(0);

  useEffect(() => {
    let cancelled = false;

    async function run() {
      setIsLoading(true);
      setError(null);

      try {
        const result = await rewriteWithGemini({
          apiKey: preferences.apiKey,
          model: preferences.model,
          instruction: request.instruction,
          sourceText: request.sourceText,
          customInstructions: preferences.customInstructions,
        });

        if (!cancelled) {
          setRewrittenText(result);
        }
      } catch (currentError) {
        if (!cancelled) {
          setError(currentError instanceof Error ? currentError.message : String(currentError));
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    }

    void run();

    return () => {
      cancelled = true;
    };
  }, [preferences.apiKey, preferences.customInstructions, preferences.model, refreshToken, request.instruction, request.sourceText]);

  const markdown = error
    ? error
    : isLoading
      ? "Generating rewrite…"
      : buildMarkdown(request.sourceText, rewrittenText);

  async function onCopy(): Promise<void> {
    if (!rewrittenText) return;

    await handleOutput("copy", rewrittenText);
    await showToast({
      style: Toast.Style.Success,
      title: "Copied rewritten text",
    });
  }

  async function onPaste(): Promise<void> {
    if (!rewrittenText) return;

    await handleOutput("paste", rewrittenText);
  }

  return (
    <Detail
      navigationTitle=""
      markdown={markdown}
      actions={
        <ActionPanel>
          <ActionPanel.Section>
            <Action
              title="Paste Result"
              icon={Icon.TextInput}
              onAction={onPaste}
            />
            <Action
              title="Copy Result"
              icon={Icon.Clipboard}
              onAction={onCopy}
            />
          </ActionPanel.Section>
          <ActionPanel.Section>
            <Action
              title="Regenerate"
              icon={Icon.ArrowClockwise}
              onAction={() => setRefreshToken((value) => value + 1)}
            />
          </ActionPanel.Section>
        </ActionPanel>
      }
    />
  );
}
