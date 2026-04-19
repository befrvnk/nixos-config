export type AnswerKeybindingsLike = {
  matches: (first: string, second: string) => boolean;
};

function matchesKeybinding(
  keybindings: AnswerKeybindingsLike,
  keybindingId: string,
  data: string,
): boolean {
  // pi's injected keybindings manager uses matches(data, keybindingId),
  // but keep a fallback for the old local mock ordering so tests can cover both.
  return (
    keybindings.matches(data, keybindingId) ||
    keybindings.matches(keybindingId, data)
  );
}

export function isAnswerCancel(
  keybindings: AnswerKeybindingsLike,
  data: string,
): boolean {
  return (
    matchesKeybinding(keybindings, "tui.select.cancel", data) ||
    matchesKeybinding(keybindings, "app.interrupt", data)
  );
}

export function isAnswerConfirm(
  keybindings: AnswerKeybindingsLike,
  data: string,
): boolean {
  return (
    matchesKeybinding(keybindings, "tui.select.confirm", data) ||
    matchesKeybinding(keybindings, "tui.input.submit", data)
  );
}

export function isAnswerNext(
  keybindings: AnswerKeybindingsLike,
  data: string,
): boolean {
  return matchesKeybinding(keybindings, "tui.input.tab", data);
}

export function isAnswerVerticalMove(
  keybindings: AnswerKeybindingsLike,
  direction: "up" | "down",
  data: string,
): boolean {
  return matchesKeybinding(
    keybindings,
    direction === "up" ? "tui.select.up" : "tui.select.down",
    data,
  );
}
