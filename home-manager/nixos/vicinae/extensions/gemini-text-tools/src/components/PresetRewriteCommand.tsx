import {
  Action,
  ActionPanel,
  Detail,
  Icon,
  Toast,
  showToast,
  useNavigation,
} from "@vicinae/api";
import { useEffect, useState } from "react";
import { CustomRewriteForm } from "./CustomRewriteForm.js";
import { RewriteResultView } from "./RewriteResultView.js";
import { presetById } from "../lib/presets.js";
import { getPreferences } from "../lib/preferences.js";
import { readSourceText } from "../lib/text.js";

export function PresetRewriteCommand({ presetId }: { presetId: string }) {
  const preset = presetById[presetId];
  const preferences = getPreferences();
  const { push } = useNavigation();
  const [sourceText, setSourceText] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [refreshToken, setRefreshToken] = useState<number>(0);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setIsLoading(true);
      setError(null);

      try {
        const text = await readSourceText(preferences.source);
        if (!cancelled) {
          setSourceText(text);
        }
      } catch (currentError) {
        if (!cancelled) {
          setSourceText("");
          setError(currentError instanceof Error ? currentError.message : String(currentError));
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    }

    void load();

    return () => {
      cancelled = true;
    };
  }, [preferences.source, refreshToken]);

  if (isLoading) {
    return <Detail navigationTitle="" markdown="Loading text…" />;
  }

  if (error || !sourceText.trim()) {
    return (
      <Detail
        navigationTitle=""
        markdown={[
          "Unable to load text to rewrite.",
          "",
          error ?? "No selected text or clipboard text was available.",
        ].join("\n")}
        actions={
          <ActionPanel>
            <Action
              title="Retry"
              icon={Icon.ArrowClockwise}
              onAction={() => setRefreshToken((value) => value + 1)}
            />
            <Action
              title="Open Custom Rewrite"
              icon={Icon.Pencil}
              onAction={() => push(<CustomRewriteForm initialText="" />)}
            />
            <Action
              title="Show Help"
              icon={Icon.Info}
              onAction={() =>
                showToast({
                  style: Toast.Style.Success,
                  title: "Tip",
                  message: "Select text before opening Vicinae, or use Custom Rewrite to paste text manually.",
                })
              }
            />
          </ActionPanel>
        }
      />
    );
  }

  return (
    <RewriteResultView
      request={{
        title: preset.title,
        instruction: preset.instruction,
        sourceText,
      }}
    />
  );
}
