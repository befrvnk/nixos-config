function replacePreservingNewlines(char: string): string {
  return char === "\n" || char === "\r" ? char : " ";
}

/** Remove JSONC comments without changing token boundaries or source offsets. */
export function stripJsonComments(text: string): string {
  let output = "";
  let inString = false;
  let escaped = false;
  let inLineComment = false;
  let inBlockComment = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]!;
    const next = text[index + 1];

    if (inLineComment) {
      if (char === "\n" || char === "\r") {
        inLineComment = false;
        output += char;
      } else {
        output += " ";
      }
      continue;
    }

    if (inBlockComment) {
      if (char === "*" && next === "/") {
        output += "  ";
        inBlockComment = false;
        index += 1;
      } else {
        output += replacePreservingNewlines(char);
      }
      continue;
    }

    if (inString) {
      output += char;
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
      output += char;
    } else if (char === "/" && next === "/") {
      output += "  ";
      inLineComment = true;
      index += 1;
    } else if (char === "/" && next === "*") {
      output += "  ";
      inBlockComment = true;
      index += 1;
    } else {
      output += char;
    }
  }

  if (inBlockComment) {
    throw new SyntaxError("Unterminated block comment in JSONC input.");
  }

  return output;
}

/** Remove commas immediately before an object or array closing delimiter. */
export function stripTrailingCommas(text: string): string {
  let output = "";
  let inString = false;
  let escaped = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]!;

    if (inString) {
      output += char;
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }

    if (char === '"') {
      inString = true;
      output += char;
      continue;
    }

    if (char === ",") {
      let nextIndex = index + 1;
      while (nextIndex < text.length && /\s/u.test(text[nextIndex]!)) nextIndex += 1;
      if (text[nextIndex] === "}" || text[nextIndex] === "]") {
        output += " ";
        continue;
      }
    }

    output += char;
  }

  return output;
}

export function parseJsonc(text: string): unknown {
  const withoutBom = text.charCodeAt(0) === 0xfeff ? ` ${text.slice(1)}` : text;
  return JSON.parse(stripTrailingCommas(stripJsonComments(withoutBom)));
}
