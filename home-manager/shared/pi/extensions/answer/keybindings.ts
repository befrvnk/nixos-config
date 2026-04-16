export type AnswerKeybindingsLike = {
  matches: (keybindingId: string, data: string) => boolean;
};

export function isAnswerCancel(
  keybindings: AnswerKeybindingsLike,
  data: string,
): boolean {
  return (
    keybindings.matches("tui.select.cancel", data) ||
    keybindings.matches("app.interrupt", data)
  );
}

export function isAnswerConfirm(
  keybindings: AnswerKeybindingsLike,
  data: string,
): boolean {
  return (
    keybindings.matches("tui.select.confirm", data) ||
    keybindings.matches("tui.input.submit", data)
  );
}

export function isAnswerNext(
  keybindings: AnswerKeybindingsLike,
  data: string,
): boolean {
  return keybindings.matches("tui.input.tab", data);
}

export function isAnswerVerticalMove(
  keybindings: AnswerKeybindingsLike,
  direction: "up" | "down",
  data: string,
): boolean {
  return keybindings.matches(
    direction === "up" ? "tui.select.up" : "tui.select.down",
    data,
  );
}
