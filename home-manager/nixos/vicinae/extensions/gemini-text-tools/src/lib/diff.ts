import { diffWordsWithSpace } from "diff";

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;")
    .replaceAll("\n", "<br/>");
}

function segmentWordCount(value: string): number {
  const matches = value.match(/\S+/g);
  return matches ? matches.length : 0;
}

export function createDiffSummary(original: string, rewritten: string): {
  addedWords: number;
  removedWords: number;
  changed: boolean;
  html: string;
} {
  const parts = diffWordsWithSpace(original, rewritten);

  let addedWords = 0;
  let removedWords = 0;

  const html = parts
    .map((part) => {
      const value = escapeHtml(part.value);

      if (part.added) {
        addedWords += segmentWordCount(part.value);
        return `<span style="background-color:#163a1f;color:#7ee787;">${value}</span>`;
      }

      if (part.removed) {
        removedWords += segmentWordCount(part.value);
        return `<span style="background-color:#4c1d1d;color:#ff7b72;text-decoration:line-through;">${value}</span>`;
      }

      return `<span>${value}</span>`;
    })
    .join("");

  return {
    addedWords,
    removedWords,
    changed: addedWords > 0 || removedWords > 0,
    html: `<span style="font-family: monospace; white-space: pre-wrap; line-height: 1.5;">${html}</span>`,
  };
}
