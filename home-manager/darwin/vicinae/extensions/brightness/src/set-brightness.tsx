import { Action, ActionPanel, Form, closeMainWindow } from "@vicinae/api";
import { useState } from "react";
import { runBrightnessAction, setBrightnessPercent } from "./lib/better-display.js";

export default function SetBrightness() {
  const [levelError, setLevelError] = useState<string | undefined>();

  async function handleSubmit(values: Form.Values): Promise<void> {
    const raw = String((values as { level?: string }).level ?? "").trim();
    const level = Number(raw);

    if (!Number.isFinite(level) || level < 0 || level > 100) {
      setLevelError("Enter a number between 0 and 100");
      return;
    }

    setLevelError(undefined);
    await runBrightnessAction("Set Brightness", () => setBrightnessPercent(level));
    await closeMainWindow();
  }

  return (
    <Form
      navigationTitle="Set Brightness"
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Set Brightness" onSubmit={handleSubmit} />
        </ActionPanel>
      }
    >
      <Form.TextField
        id="level"
        title="Brightness (%)"
        placeholder="0-100"
        error={levelError}
        onChange={() => setLevelError(undefined)}
      />
    </Form>
  );
}
