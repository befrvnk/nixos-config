type SyntaxColor =
  | "syntaxComment"
  | "syntaxKeyword"
  | "syntaxFunction"
  | "syntaxVariable"
  | "syntaxString"
  | "syntaxNumber"
  | "syntaxType"
  | "syntaxOperator"
  | "syntaxPunctuation";

export type KotlinHighlightTheme = {
  fg: (color: SyntaxColor, text: string) => string;
  italic: (text: string) => string;
};

type TokenKind =
  | "plain"
  | "annotation"
  | "chainFunction"
  | "comment"
  | "function"
  | "keyword"
  | "number"
  | "operator"
  | "punctuation"
  | "string"
  | "type"
  | "variable";

type KotlinLexerState = {
  afterFun: boolean;
  inBlockComment: boolean;
  inTripleString: boolean;
  lastSignificantChar?: string;
};

const KEYWORDS = new Set([
  "as",
  "break",
  "by",
  "catch",
  "class",
  "companion",
  "constructor",
  "continue",
  "data",
  "do",
  "else",
  "enum",
  "false",
  "finally",
  "for",
  "fun",
  "if",
  "import",
  "in",
  "interface",
  "internal",
  "is",
  "null",
  "object",
  "out",
  "override",
  "package",
  "private",
  "protected",
  "public",
  "return",
  "sealed",
  "super",
  "this",
  "throw",
  "true",
  "try",
  "typealias",
  "val",
  "var",
  "vararg",
  "when",
  "where",
  "while",
]);

const SOFT_KEYWORDS = new Set([
  "actual",
  "abstract",
  "annotation",
  "const",
  "crossinline",
  "expect",
  "external",
  "final",
  "infix",
  "inline",
  "inner",
  "lateinit",
  "noinline",
  "open",
  "operator",
  "reified",
  "suspend",
  "tailrec",
  "value",
]);

const CONTROL_CALLS = new Set([
  "catch",
  "do",
  "else",
  "for",
  "if",
  "return",
  "try",
  "when",
  "while",
]);

const BUILTIN_TYPES = new Set([
  "Any",
  "Array",
  "Boolean",
  "Byte",
  "Char",
  "CharSequence",
  "Collection",
  "Comparable",
  "Double",
  "Enum",
  "Float",
  "Int",
  "Iterable",
  "List",
  "Long",
  "Map",
  "MutableCollection",
  "MutableIterable",
  "MutableList",
  "MutableMap",
  "MutableSet",
  "Nothing",
  "Pair",
  "Result",
  "Sequence",
  "Set",
  "Short",
  "String",
  "Triple",
  "Unit",
]);

const OPERATOR_CHARS = new Set([
  "+",
  "-",
  "*",
  "/",
  "%",
  "=",
  "!",
  "<",
  ">",
  "?",
  ":",
  "&",
  "|",
  "^",
  "~",
]);

const PUNCTUATION_CHARS = new Set(["(", ")", "{", "}", "[", "]", ";", ",", "."]);

function isIdentifierStart(char: string | undefined): boolean {
  return !!char && /[A-Za-z_]/.test(char);
}

function isIdentifierPart(char: string | undefined): boolean {
  return !!char && /[A-Za-z0-9_]/.test(char);
}

function isDigit(char: string | undefined): boolean {
  return !!char && /[0-9]/.test(char);
}

function isUppercaseIdentifier(identifier: string): boolean {
  return /^[A-Z]/.test(identifier);
}

function nextNonWhitespace(line: string, index: number): string | undefined {
  for (let i = index; i < line.length; i += 1) {
    if (!/\s/.test(line[i])) return line[i];
  }
  return undefined;
}

function previousNonWhitespace(
  line: string,
  index: number,
  fallback: string | undefined,
): string | undefined {
  for (let i = index; i >= 0; i -= 1) {
    if (!/\s/.test(line[i])) return line[i];
  }
  return fallback;
}

function lastNonWhitespace(text: string): string | undefined {
  for (let i = text.length - 1; i >= 0; i -= 1) {
    if (!/\s/.test(text[i])) return text[i];
  }
  return undefined;
}

function updateLastSignificantChar(state: KotlinLexerState, text: string) {
  const char = lastNonWhitespace(text);
  if (char) state.lastSignificantChar = char;
}

function styleToken(
  theme: KotlinHighlightTheme,
  kind: TokenKind,
  text: string,
): string {
  if (!text) return text;

  switch (kind) {
    case "annotation":
    case "type":
      return theme.fg("syntaxType", text);
    case "chainFunction":
      return theme.fg("syntaxFunction", theme.italic(text));
    case "comment":
      return theme.fg("syntaxComment", text);
    case "function":
      return theme.fg("syntaxFunction", text);
    case "keyword":
      return theme.fg("syntaxKeyword", text);
    case "number":
      return theme.fg("syntaxNumber", text);
    case "operator":
      return theme.fg("syntaxOperator", text);
    case "punctuation":
      return theme.fg("syntaxPunctuation", text);
    case "string":
      return theme.fg("syntaxString", text);
    case "variable":
      return theme.fg("syntaxVariable", text);
    case "plain":
    default:
      return text;
  }
}

function pushToken(
  parts: string[],
  state: KotlinLexerState,
  theme: KotlinHighlightTheme,
  kind: TokenKind,
  text: string,
) {
  parts.push(styleToken(theme, kind, text));
  updateLastSignificantChar(state, text);
}

function readLineComment(line: string, index: number): [text: string, nextIndex: number] {
  return [line.slice(index), line.length];
}

function readBlockComment(
  line: string,
  index: number,
  state: KotlinLexerState,
): [text: string, nextIndex: number] {
  const end = line.indexOf("*/", index + (state.inBlockComment ? 0 : 2));
  if (end === -1) {
    state.inBlockComment = true;
    return [line.slice(index), line.length];
  }
  state.inBlockComment = false;
  return [line.slice(index, end + 2), end + 2];
}

function readTripleString(
  line: string,
  index: number,
  state: KotlinLexerState,
): [text: string, nextIndex: number] {
  const searchFrom = index + (state.inTripleString ? 0 : 3);
  const end = line.indexOf('"""', searchFrom);
  if (end === -1) {
    state.inTripleString = true;
    return [line.slice(index), line.length];
  }
  state.inTripleString = false;
  return [line.slice(index, end + 3), end + 3];
}

function readQuotedString(line: string, index: number): [text: string, nextIndex: number] {
  let i = index + 1;
  let escaped = false;

  for (; i < line.length; i += 1) {
    const char = line[i];
    if (escaped) {
      escaped = false;
    } else if (char === "\\") {
      escaped = true;
    } else if (char === '"') {
      i += 1;
      break;
    }
  }

  return [line.slice(index, i), i];
}

function readCharLiteral(line: string, index: number): [text: string, nextIndex: number] {
  let i = index + 1;
  let escaped = false;

  for (; i < line.length; i += 1) {
    const char = line[i];
    if (escaped) {
      escaped = false;
    } else if (char === "\\") {
      escaped = true;
    } else if (char === "'") {
      i += 1;
      break;
    }
  }

  return [line.slice(index, i), i];
}

function readBacktickIdentifier(line: string, index: number): [text: string, nextIndex: number] {
  const end = line.indexOf("`", index + 1);
  if (end === -1) return [line.slice(index), line.length];
  return [line.slice(index, end + 1), end + 1];
}

function readNumber(line: string, index: number): [text: string, nextIndex: number] {
  let i = index;
  if (line.startsWith("0x", index) || line.startsWith("0X", index)) {
    i += 2;
    while (/[0-9a-fA-F_]/.test(line[i] ?? "")) i += 1;
  } else if (line.startsWith("0b", index) || line.startsWith("0B", index)) {
    i += 2;
    while (/[01_]/.test(line[i] ?? "")) i += 1;
  } else {
    while (/[0-9_]/.test(line[i] ?? "")) i += 1;
    if (line[i] === "." && isDigit(line[i + 1])) {
      i += 1;
      while (/[0-9_]/.test(line[i] ?? "")) i += 1;
    }
    if (line[i] === "e" || line[i] === "E") {
      const exponentStart = i;
      i += 1;
      if (line[i] === "+" || line[i] === "-") i += 1;
      if (isDigit(line[i])) {
        while (/[0-9_]/.test(line[i] ?? "")) i += 1;
      } else {
        i = exponentStart;
      }
    }
  }

  while (/[uUlLfF]/.test(line[i] ?? "")) i += 1;
  return [line.slice(index, i), i];
}

function readIdentifier(line: string, index: number): [text: string, nextIndex: number] {
  let i = index + 1;
  while (isIdentifierPart(line[i])) i += 1;
  return [line.slice(index, i), i];
}

function readRepeatedChars(
  line: string,
  index: number,
  allowed: Set<string>,
): [text: string, nextIndex: number] {
  let i = index + 1;
  while (allowed.has(line[i] ?? "")) i += 1;
  return [line.slice(index, i), i];
}

function classifyIdentifier(
  identifier: string,
  line: string,
  index: number,
  end: number,
  state: KotlinLexerState,
): TokenKind {
  const keyword = KEYWORDS.has(identifier) || SOFT_KEYWORDS.has(identifier);
  const previous = previousNonWhitespace(line, index - 1, state.lastSignificantChar);
  const next = nextNonWhitespace(line, end);
  const isCallLike = next === "(" || next === "{";
  const isChainedCall = previous === "." && isCallLike;

  if (keyword) {
    if (identifier === "fun") state.afterFun = true;
    return "keyword";
  }

  if (state.afterFun && isCallLike) {
    state.afterFun = false;
    return "function";
  }

  if (isChainedCall) return "chainFunction";

  if (isCallLike && !CONTROL_CALLS.has(identifier)) {
    return isUppercaseIdentifier(identifier) ? "type" : "function";
  }

  if (BUILTIN_TYPES.has(identifier) || isUppercaseIdentifier(identifier)) {
    return "type";
  }

  return "plain";
}

function highlightKotlinLine(
  line: string,
  state: KotlinLexerState,
  theme: KotlinHighlightTheme,
): string {
  const parts: string[] = [];
  let i = 0;

  while (i < line.length) {
    if (state.inBlockComment) {
      const [text, nextIndex] = readBlockComment(line, i, state);
      pushToken(parts, state, theme, "comment", text);
      i = nextIndex;
      continue;
    }

    if (state.inTripleString) {
      const [text, nextIndex] = readTripleString(line, i, state);
      pushToken(parts, state, theme, "string", text);
      i = nextIndex;
      continue;
    }

    const char = line[i];

    if (line.startsWith("//", i)) {
      const [text, nextIndex] = readLineComment(line, i);
      pushToken(parts, state, theme, "comment", text);
      i = nextIndex;
      continue;
    }

    if (line.startsWith("/*", i)) {
      const [text, nextIndex] = readBlockComment(line, i, state);
      pushToken(parts, state, theme, "comment", text);
      i = nextIndex;
      continue;
    }

    if (line.startsWith('"""', i)) {
      const [text, nextIndex] = readTripleString(line, i, state);
      pushToken(parts, state, theme, "string", text);
      i = nextIndex;
      continue;
    }

    if (char === '"') {
      const [text, nextIndex] = readQuotedString(line, i);
      pushToken(parts, state, theme, "string", text);
      i = nextIndex;
      continue;
    }

    if (char === "'") {
      const [text, nextIndex] = readCharLiteral(line, i);
      pushToken(parts, state, theme, "string", text);
      i = nextIndex;
      continue;
    }

    if (char === "`") {
      const [text, nextIndex] = readBacktickIdentifier(line, i);
      const previous = previousNonWhitespace(line, i - 1, state.lastSignificantChar);
      const next = nextNonWhitespace(line, nextIndex);
      const kind = previous === "." && (next === "(" || next === "{")
        ? "chainFunction"
        : next === "(" || next === "{"
          ? "function"
          : "plain";
      pushToken(parts, state, theme, kind, text);
      i = nextIndex;
      continue;
    }

    if (char === "@" && isIdentifierStart(line[i + 1])) {
      const [identifier, nextIndex] = readIdentifier(line, i + 1);
      pushToken(parts, state, theme, "annotation", `@${identifier}`);
      i = nextIndex;
      continue;
    }

    if (isDigit(char)) {
      const [text, nextIndex] = readNumber(line, i);
      pushToken(parts, state, theme, "number", text);
      i = nextIndex;
      continue;
    }

    if (isIdentifierStart(char)) {
      const [identifier, nextIndex] = readIdentifier(line, i);
      const kind = classifyIdentifier(identifier, line, i, nextIndex, state);
      pushToken(parts, state, theme, kind, identifier);
      i = nextIndex;
      continue;
    }

    if (OPERATOR_CHARS.has(char)) {
      const [text, nextIndex] = readRepeatedChars(line, i, OPERATOR_CHARS);
      pushToken(parts, state, theme, "operator", text);
      i = nextIndex;
      continue;
    }

    if (PUNCTUATION_CHARS.has(char)) {
      pushToken(parts, state, theme, "punctuation", char);
      i += 1;
      continue;
    }

    pushToken(parts, state, theme, "plain", char);
    i += 1;
  }

  return parts.join("");
}

export function highlightKotlinCode(
  code: string,
  theme: KotlinHighlightTheme,
): string[] {
  const state: KotlinLexerState = {
    afterFun: false,
    inBlockComment: false,
    inTripleString: false,
  };

  return code.split("\n").map((line) => highlightKotlinLine(line, state, theme));
}
