import {
  Action,
  ActionPanel,
  Icon,
  List,
  Toast,
  showToast,
  useNavigation,
} from "@vicinae/api";
import { useEffect, useState } from "react";
import { runQuickPreset } from "./lib/actions.js";
import { presets } from "./lib/presets.js";
import { getPreferences } from "./lib/preferences.js";
import { readSourceText } from "./lib/text.js";
import type { RewritePreset } from "./lib/types.js";
import { RewriteResultView } from "./components/RewriteResultView.js";
import { CustomRewriteForm } from "./components/CustomRewriteForm.js";

function detailMarkdown(sourceText: string, preset: RewritePreset): string {
  return [
    `# ${preset.title}`,
    "",
    preset.description,
    "",
    "## Instruction",
    preset.instruction,
    "",
    "## Current Source Text",
    sourceText ? `\`\`\`text\n${sourceText}\n\`\`\`` : "No text detected yet.",
  ].join("\n");
}

export default function RewriteTextCommand() {
  const preferences = getPreferences();
  const { push } = useNavigation();
  const [sourceText, setSourceText] = useState<string>("");
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);

  const openPresetPreview = (preset: RewritePreset): void => {
    if (!sourceText.trim()) {
      void showToast({
        style: Toast.Style.Failure,
        title: "No text loaded",
        message: "Refresh the source text or use Custom Rewrite to paste text manually.",
      });
      return;
    }

    push(
      <RewriteResultView
        request={{
          title: preset.title,
          instruction: preset.instruction,
          sourceText,
        }}
      />,
    );
  };

  const refreshSourceText = async (): Promise<void> => {
    setIsLoading(true);
    setLoadError(null);

    try {
      const text = await readSourceText(preferences.source);
      setSourceText(text);
    } catch (error) {
      setSourceText("");
      setLoadError(error instanceof Error ? error.message : String(error));
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    void refreshSourceText();
  }, []);

  return (
    <List isLoading={isLoading} isShowingDetail searchBarPlaceholder="Filter rewrite presets">
      {loadError ? (
        <List.Section title="Input Status">
          <List.Item
            title="No text detected"
            subtitle={loadError}
            actions={
              <ActionPanel>
                <Action
                  title="Open Custom Rewrite"
                  icon={Icon.Pencil}
                  onAction={() => push(<CustomRewriteForm initialText="" />)}
                />
                <Action
                  title="Refresh Source Text"
                  icon={Icon.ArrowClockwise}
                  onAction={refreshSourceText}
                />
              </ActionPanel>
            }
          />
        </List.Section>
      ) : null}

      <List.Section title="Presets">
        {presets.map((preset) => (
          <List.Item
            key={preset.id}
            title={preset.title}
            subtitle={preset.description}
            keywords={preset.keywords}
            detail={<List.Item.Detail markdown={detailMarkdown(sourceText, preset)} />}
            actions={
              <ActionPanel>
                <ActionPanel.Section>
                  <Action
                    title="Generate Preview"
                    icon={Icon.Eye}
                    onAction={() => openPresetPreview(preset)}
                  />
                  <Action
                    title={preferences.action === "paste" ? "Apply Immediately" : "Copy Immediately"}
                    icon={preferences.action === "paste" ? Icon.TextInput : Icon.Clipboard}
                    onAction={() => runQuickPreset(preset)}
                  />
                </ActionPanel.Section>
                <ActionPanel.Section>
                  <Action
                    title="Custom Rewrite"
                    icon={Icon.Pencil}
                    onAction={() => push(<CustomRewriteForm initialText={sourceText} />)}
                  />
                  <Action
                    title="Refresh Source Text"
                    icon={Icon.ArrowClockwise}
                    onAction={refreshSourceText}
                  />
                  <Action
                    title="Show Current Source Length"
                    icon={Icon.Text}
                    onAction={() =>
                      showToast({
                        style: Toast.Style.Success,
                        title: sourceText ? `${sourceText.length} characters loaded` : "No text loaded",
                      })
                    }
                  />
                </ActionPanel.Section>
              </ActionPanel>
            }
          />
        ))}
      </List.Section>
    </List>
  );
}
