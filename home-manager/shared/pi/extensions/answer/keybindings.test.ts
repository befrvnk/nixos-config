import assert from "node:assert/strict";
import test from "node:test";
import {
  isAnswerCancel,
  isAnswerConfirm,
  isAnswerNext,
  isAnswerVerticalMove,
  type AnswerKeybindingsLike,
} from "./keybindings.ts";

function createDataFirstKeybindings(bindings: Record<string, string>): AnswerKeybindingsLike {
  return {
    matches(data, id) {
      return bindings[id] === data;
    },
  };
}

function createIdFirstKeybindings(bindings: Record<string, string>): AnswerKeybindingsLike {
  return {
    matches(id, data) {
      return bindings[id] === data;
    },
  };
}

for (const [label, createKeybindings] of [
  ["data-first", createDataFirstKeybindings],
  ["id-first fallback", createIdFirstKeybindings],
] as const) {
  test(`answer keybinding helpers respect injected keybinding ids (${label})`, () => {
    const keybindings = createKeybindings({
      "tui.select.cancel": "custom-cancel",
      "app.interrupt": "custom-interrupt",
      "tui.select.confirm": "custom-confirm",
      "tui.input.submit": "custom-submit",
      "tui.input.tab": "custom-tab",
      "tui.select.up": "custom-up",
      "tui.select.down": "custom-down",
    });

    assert.equal(isAnswerCancel(keybindings, "custom-cancel"), true);
    assert.equal(isAnswerCancel(keybindings, "custom-interrupt"), true);
    assert.equal(isAnswerConfirm(keybindings, "custom-confirm"), true);
    assert.equal(isAnswerConfirm(keybindings, "custom-submit"), true);
    assert.equal(isAnswerNext(keybindings, "custom-tab"), true);
    assert.equal(isAnswerVerticalMove(keybindings, "up", "custom-up"), true);
    assert.equal(isAnswerVerticalMove(keybindings, "down", "custom-down"), true);
    assert.equal(isAnswerNext(keybindings, "tab"), false);
  });
}
