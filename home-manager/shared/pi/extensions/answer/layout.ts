export interface AnswerLayout {
  renderWidth: number;
  boxWidth: number;
  contentWidth: number;
  editorWidth: number;
  compact: boolean;
}

export function calculateAnswerLayout(width: number): AnswerLayout {
  const renderWidth = Math.max(0, Math.floor(width));
  const boxWidth = Math.min(Math.max(0, renderWidth - 4), 120);
  const contentWidth = Math.max(0, boxWidth - 4);
  return {
    renderWidth,
    boxWidth,
    contentWidth,
    editorWidth: Math.max(1, contentWidth - 7),
    compact: boxWidth < 8,
  };
}
