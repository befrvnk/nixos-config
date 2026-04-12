import {
  Action,
  ActionPanel,
  Form,
  Icon,
  Toast,
  showToast,
  useNavigation,
} from "@vicinae/api";
import { useState } from "react";
import { RewriteResultView } from "./RewriteResultView.js";

type CustomRewriteValues = {
  instruction: string;
  sourceText: string;
};

export function CustomRewriteForm({ initialText }: { initialText: string }) {
  const { push } = useNavigation();
  const [instructionError, setInstructionError] = useState<string | undefined>();
  const [textError, setTextError] = useState<string | undefined>();

  async function handleSubmit(values: Form.Values): Promise<void> {
    const instruction = String((values as CustomRewriteValues).instruction ?? "").trim();
    const sourceText = String((values as CustomRewriteValues).sourceText ?? "");

    if (!instruction) {
      setInstructionError("Instructions are required");
      return;
    }

    if (!sourceText.trim()) {
      setTextError("Text is required");
      return;
    }

    setInstructionError(undefined);
    setTextError(undefined);

    push(
      <RewriteResultView
        request={{
          title: "Custom Rewrite",
          instruction,
          sourceText,
        }}
      />,
    );
  }

  return (
    <Form
      navigationTitle="Custom Rewrite"
      actions={
        <ActionPanel>
          <Action.SubmitForm
            title="Generate Rewrite"
            icon={Icon.Stars}
            onSubmit={handleSubmit}
          />
          <Action
            title="Need Text Source"
            icon={Icon.Info}
            onAction={() =>
              showToast({
                style: Toast.Style.Success,
                title: "Tip",
                message: "Paste text directly into the form if no selection is available.",
              })
            }
          />
        </ActionPanel>
      }
    >
      <Form.TextArea
        id="instruction"
        title="Instructions"
        error={instructionError}
        onChange={() => setInstructionError(undefined)}
        defaultValue="Rewrite the text to improve clarity and flow while preserving meaning."
      />
      <Form.TextArea
        id="sourceText"
        title="Text"
        error={textError}
        onChange={() => setTextError(undefined)}
        defaultValue={initialText}
      />
    </Form>
  );
}
