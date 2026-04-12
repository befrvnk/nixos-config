import { Toast, showToast } from "@vicinae/api";

type GeminiPart = {
  text?: string;
};

type GeminiCandidate = {
  content?: {
    parts?: GeminiPart[];
  };
  finishReason?: string;
};

type GeminiResponse = {
  candidates?: GeminiCandidate[];
  promptFeedback?: {
    blockReason?: string;
    blockReasonMessage?: string;
  };
  error?: {
    message?: string;
  };
};

function buildPrompt(instruction: string, text: string, customInstructions: string): string {
  const extra = customInstructions.trim();

  return [
    "You are an expert writing assistant.",
    "Rewrite the provided text according to the instruction below.",
    "Return only the rewritten text.",
    "Do not add commentary, headings, explanations, or quotation marks unless they are already part of the text.",
    "",
    `Instruction: ${instruction}`,
    extra ? `Additional instructions: ${extra}` : "",
    "",
    "Text:",
    text,
  ]
    .filter(Boolean)
    .join("\n");
}

export async function rewriteWithGemini(options: {
  apiKey: string;
  model: string;
  instruction: string;
  sourceText: string;
  customInstructions: string;
}): Promise<string> {
  const { apiKey, model, instruction, sourceText, customInstructions } = options;

  if (!apiKey.trim()) {
    throw new Error("Gemini API key is not configured. Open Vicinae preferences for Gemini Text Tools and add your API key.");
  }

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              {
                text: buildPrompt(instruction, sourceText, customInstructions),
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.4,
          responseMimeType: "text/plain",
        },
      }),
    },
  );

  const data = (await response.json()) as GeminiResponse;

  if (!response.ok) {
    throw new Error(data.error?.message ?? `Gemini request failed with status ${response.status}.`);
  }

  if (data.promptFeedback?.blockReason) {
    throw new Error(
      data.promptFeedback.blockReasonMessage ??
        `Gemini blocked this request (${data.promptFeedback.blockReason}).`,
    );
  }

  const text = data.candidates
    ?.flatMap((candidate) => candidate.content?.parts ?? [])
    .map((part) => part.text ?? "")
    .join("\n")
    .trim();

  if (!text) {
    const finishReason = data.candidates?.[0]?.finishReason;
    throw new Error(
      finishReason
        ? `Gemini returned no text (finish reason: ${finishReason}).`
        : "Gemini returned no text.",
    );
  }

  return text;
}

export async function showGeminiError(title: string, error: unknown): Promise<void> {
  await showToast({
    style: Toast.Style.Failure,
    title,
    message: error instanceof Error ? error.message : String(error),
  });
}
