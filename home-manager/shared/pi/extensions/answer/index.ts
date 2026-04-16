/**
 * Interactive answer command for pi.
 *
 * Adapted from mitsuhiko/agent-stuff's pi-extensions/answer.ts
 * and adjusted for this repo's pi setup.
 */

import { complete, type Api, type Model, type UserMessage } from "@mariozechner/pi-ai";
import {
	BorderedLoader,
	keyHint,
	rawKeyHint,
	type ExtensionAPI,
	type ExtensionCommandContext,
	type ModelRegistry,
	type Theme,
} from "@mariozechner/pi-coding-agent";
import {
	type Component,
	Editor,
	type EditorTheme,
	Key,
	matchesKey,
	type TUI,
	truncateToWidth,
	visibleWidth,
	wrapTextWithAnsi,
} from "@mariozechner/pi-tui";

import {
	buildAnswerMessage,
	findLastAssistantText,
	parseExtractionResult,
	prepareAssistantTextForExtraction,
	type ExtractedQuestion,
	type ExtractionResult,
} from "./helpers.ts";
import {
	isAnswerCancel,
	isAnswerConfirm,
	isAnswerNext,
	isAnswerVerticalMove,
	type AnswerKeybindingsLike,
} from "./keybindings.ts";

const SYSTEM_PROMPT = `You are a question extractor. Given text from a conversation, extract any questions that need answering.

Output a JSON object with this structure:
{
  "questions": [
    {
      "question": "The question text",
      "context": "Optional context that helps answer the question"
    }
  ]
}

Rules:
- Extract all questions that require user input
- Keep questions in the order they appeared
- Be concise with question text
- Include context only when it provides essential information for answering
- If no questions are found, return {"questions": []}`;

const EXTRACTION_MODEL_CANDIDATES = [
	["github-copilot", "gpt-5.4-mini"],
	["github-copilot", "claude-sonnet-4.6"],
	["github-copilot", "gemini-3.1-pro-preview"],
] as const;

type ExtractionUiResult =
	| { status: "success"; value: ExtractionResult }
	| { status: "cancelled" }
	| { status: "error"; message: string };

async function hasModelAuth(model: Model<Api>, modelRegistry: ModelRegistry) {
	const auth = await modelRegistry.getApiKeyAndHeaders(model);
	return auth.ok && Boolean(auth.apiKey);
}

async function selectExtractionModel(
	currentModel: Model<Api>,
	modelRegistry: ModelRegistry,
): Promise<Model<Api>> {
	for (const [provider, id] of EXTRACTION_MODEL_CANDIDATES) {
		const model = modelRegistry.find(provider, id);
		if (!model) continue;
		if (await hasModelAuth(model, modelRegistry)) return model;
	}

	return currentModel;
}

class QnAComponent implements Component {
	private readonly questions: readonly ExtractedQuestion[];
	private readonly answers: string[];
	private readonly editor: Editor;
	private readonly tui: TUI;
	private readonly theme: Theme;
	private readonly keybindings: AnswerKeybindingsLike;
	private readonly onDone: (result: string | null) => void;
	private currentIndex = 0;
	private showingConfirmation = false;
	private cachedWidth?: number;
	private cachedLines?: string[];

	constructor(
		questions: readonly ExtractedQuestion[],
		tui: TUI,
		theme: Theme,
		keybindings: AnswerKeybindingsLike,
		onDone: (result: string | null) => void,
	) {
		this.questions = questions;
		this.answers = questions.map(() => "");
		this.tui = tui;
		this.theme = theme;
		this.keybindings = keybindings;
		this.onDone = onDone;

		const editorTheme: EditorTheme = {
			borderColor: (text: string) => theme.fg("accent", text),
			selectList: {
				selectedBg: (text: string) => theme.bg("selectedBg", text),
				matchHighlight: (text: string) => theme.fg("accent", text),
				itemSecondary: (text: string) => theme.fg("muted", text),
			},
		};

		this.editor = new Editor(tui, editorTheme);
		this.editor.disableSubmit = true;
		this.editor.onChange = () => {
			this.invalidate();
			this.tui.requestRender();
		};
	}

	invalidate() {
		this.cachedWidth = undefined;
		this.cachedLines = undefined;
	}

	private dim(text: string) {
		return this.theme.fg("dim", text);
	}

	private muted(text: string) {
		return this.theme.fg("muted", text);
	}

	private accent(text: string) {
		return this.theme.fg("accent", text);
	}

	private success(text: string) {
		return this.theme.fg("success", text);
	}

	private warning(text: string) {
		return this.theme.fg("warning", text);
	}

	private saveCurrentAnswer() {
		this.answers[this.currentIndex] = this.editor.getText();
	}

	private navigateTo(index: number) {
		if (index < 0 || index >= this.questions.length) return;
		this.saveCurrentAnswer();
		this.currentIndex = index;
		this.editor.setText(this.answers[index] || "");
		this.invalidate();
	}

	private submit() {
		this.saveCurrentAnswer();
		this.onDone(buildAnswerMessage(this.questions, this.answers));
	}

	private matchesCancel(data: string) {
		return isAnswerCancel(this.keybindings, data);
	}

	private matchesConfirm(data: string) {
		return isAnswerConfirm(this.keybindings, data);
	}

	private navigationHintText() {
		return [
			keyHint("tui.input.tab", "next"),
			rawKeyHint("shift+tab", "prev"),
			keyHint("tui.input.newLine", "newline"),
			keyHint("tui.select.cancel", "cancel"),
		].join(" · ");
	}

	private confirmationHintText() {
		return `${this.warning("Submit all answers?")} ${this.dim(`(${keyHint("tui.select.confirm", "confirm")}, y confirm, ${keyHint("tui.select.cancel", "cancel")}, n cancel)`)}`;
	}

	handleInput(data: string) {
		if (this.showingConfirmation) {
			if (this.matchesConfirm(data) || data.toLowerCase() === "y") {
				this.submit();
				return;
			}
			if (this.matchesCancel(data) || data.toLowerCase() === "n") {
				this.showingConfirmation = false;
				this.invalidate();
				this.tui.requestRender();
				return;
			}
			return;
		}

		if (this.matchesCancel(data)) {
			this.onDone(null);
			return;
		}

		if (isAnswerNext(this.keybindings, data)) {
			if (this.currentIndex < this.questions.length - 1) {
				this.navigateTo(this.currentIndex + 1);
				this.tui.requestRender();
			}
			return;
		}

		if (matchesKey(data, Key.shift("tab"))) {
			if (this.currentIndex > 0) {
				this.navigateTo(this.currentIndex - 1);
				this.tui.requestRender();
			}
			return;
		}

		if (isAnswerVerticalMove(this.keybindings, "up", data) && this.editor.getText() === "") {
			if (this.currentIndex > 0) {
				this.navigateTo(this.currentIndex - 1);
				this.tui.requestRender();
				return;
			}
		}

		if (isAnswerVerticalMove(this.keybindings, "down", data) && this.editor.getText() === "") {
			if (this.currentIndex < this.questions.length - 1) {
				this.navigateTo(this.currentIndex + 1);
				this.tui.requestRender();
				return;
			}
		}

		if (this.matchesConfirm(data) && !matchesKey(data, Key.shift("enter"))) {
			this.saveCurrentAnswer();
			if (this.currentIndex < this.questions.length - 1) {
				this.navigateTo(this.currentIndex + 1);
			} else {
				this.showingConfirmation = true;
			}
			this.invalidate();
			this.tui.requestRender();
			return;
		}

		this.editor.handleInput(data);
		this.invalidate();
		this.tui.requestRender();
	}

	render(width: number): string[] {
		if (this.cachedLines && this.cachedWidth === width) return this.cachedLines;

		const lines: string[] = [];
		const boxWidth = Math.max(Math.min(width - 4, 120), 30);
		const contentWidth = boxWidth - 4;
		const horizontalLine = (count: number) => "─".repeat(count);

		const boxLine = (content: string, leftPad = 2) => {
			const clippedContent = truncateToWidth(content, Math.max(boxWidth - 2 - leftPad, 0));
			const paddedContent = " ".repeat(leftPad) + clippedContent;
			const contentLength = visibleWidth(paddedContent);
			const rightPad = Math.max(0, boxWidth - contentLength - 2);
			return this.dim("│") + paddedContent + " ".repeat(rightPad) + this.dim("│");
		};

		const emptyBoxLine = () => this.dim("│") + " ".repeat(boxWidth - 2) + this.dim("│");
		const padToWidth = (line: string) => line + " ".repeat(Math.max(0, width - visibleWidth(line)));
		const question = this.questions[this.currentIndex];

		lines.push(padToWidth(this.dim("╭" + horizontalLine(boxWidth - 2) + "╮")));
		lines.push(
			padToWidth(
				boxLine(
					`${this.theme.bold(this.accent("Questions"))} ${this.dim(`(${this.currentIndex + 1}/${this.questions.length})`)}`,
				),
			),
		);
		lines.push(padToWidth(this.dim("├" + horizontalLine(boxWidth - 2) + "┤")));

		const progressDots = this.questions.map((_, index) => {
			if (index === this.currentIndex) return this.accent("●");
			if (this.answers[index]?.trim()) return this.success("●");
			return this.dim("○");
		});
		lines.push(padToWidth(boxLine(progressDots.join(" "))));
		lines.push(padToWidth(emptyBoxLine()));

		for (const line of wrapTextWithAnsi(`${this.theme.bold("Q:")} ${question.question}`, contentWidth)) {
			lines.push(padToWidth(boxLine(line)));
		}

		if (question.context) {
			lines.push(padToWidth(emptyBoxLine()));
			for (const line of wrapTextWithAnsi(this.muted(`> ${question.context}`), contentWidth)) {
				lines.push(padToWidth(boxLine(line)));
			}
		}

		lines.push(padToWidth(emptyBoxLine()));

		const editorWidth = Math.max(contentWidth - 7, 10);
		const editorLines = this.editor.render(editorWidth);
		for (let index = 1; index < editorLines.length - 1; index += 1) {
			if (index === 1) {
				lines.push(padToWidth(boxLine(`${this.theme.bold("A:")} ${editorLines[index]}`)));
			} else {
				lines.push(padToWidth(boxLine(`   ${editorLines[index]}`)));
			}
		}

		lines.push(padToWidth(emptyBoxLine()));
		lines.push(padToWidth(this.dim("├" + horizontalLine(boxWidth - 2) + "┤")));

		if (this.showingConfirmation) {
			lines.push(
				padToWidth(
					boxLine(truncateToWidth(this.confirmationHintText(), contentWidth)),
				),
			);
		} else {
			lines.push(
				padToWidth(
					boxLine(
						truncateToWidth(this.dim(this.navigationHintText()), contentWidth),
					),
				),
			);
		}

		lines.push(padToWidth(this.dim("╰" + horizontalLine(boxWidth - 2) + "╯")));

		this.cachedWidth = width;
		this.cachedLines = lines;
		return lines;
	}
}

export default function answerExtension(pi: ExtensionAPI) {
	const answerHandler = async (ctx: ExtensionCommandContext) => {
		if (!ctx.hasUI) {
			ctx.ui.notify("answer requires interactive mode", "error");
			return;
		}

		if (!ctx.model) {
			ctx.ui.notify("No model selected", "error");
			return;
		}

		const lastAssistant = findLastAssistantText(ctx.sessionManager.getBranch());
		if (lastAssistant.error) {
			ctx.ui.notify(lastAssistant.error, "error");
			return;
		}

		const extractionModel = await selectExtractionModel(ctx.model, ctx.modelRegistry);
		const extraction = await ctx.ui.custom<ExtractionUiResult>((tui: TUI, theme: Theme, _kb, done) => {
			const loader = new BorderedLoader(tui, theme, `Extracting questions using ${extractionModel.id}...`);
			loader.onAbort = () => done({ status: "cancelled" });

			const extract = async () => {
				const auth = await ctx.modelRegistry.getApiKeyAndHeaders(extractionModel);
				if (!auth.ok || !auth.apiKey) {
					return {
						status: "error",
						message: auth.ok ? `No API key for ${extractionModel.provider}` : auth.error,
					} as const;
				}

				const message: UserMessage = {
					role: "user",
					content: [
						{
							type: "text",
							text: prepareAssistantTextForExtraction(lastAssistant.text!),
						},
					],
					timestamp: Date.now(),
				};

				const response = await complete(
					extractionModel,
					{ systemPrompt: SYSTEM_PROMPT, messages: [message] },
					{ apiKey: auth.apiKey, headers: auth.headers, signal: loader.signal },
				);

				if (response.stopReason === "aborted") return { status: "cancelled" } as const;

				const responseText = response.content
					.filter(
						(content: { type: string; text?: string }): content is { type: "text"; text: string } =>
							content.type === "text" && typeof content.text === "string",
					)
					.map((content: { type: "text"; text: string }) => content.text)
					.join("\n");

				const parsed = parseExtractionResult(responseText);
				if (!parsed) {
					return {
						status: "error",
						message: "Question extraction returned invalid JSON",
					} as const;
				}

				return { status: "success", value: parsed } as const;
			};

			extract()
				.then(done)
				.catch((error) => {
					done({
						status: "error",
						message: error instanceof Error ? error.message : String(error),
					});
				});

			return loader;
		});

		if (extraction.status === "cancelled") {
			ctx.ui.notify("Cancelled", "info");
			return;
		}

		if (extraction.status === "error") {
			ctx.ui.notify(`Question extraction failed: ${extraction.message}`, "error");
			return;
		}

		if (extraction.value.questions.length === 0) {
			ctx.ui.notify("No questions found in the last message", "info");
			return;
		}

		const answers = await ctx.ui.custom<string | null>((tui: TUI, theme: Theme, keybindings, done) =>
			new QnAComponent(extraction.value.questions, tui, theme, keybindings, done),
		);

		if (answers === null) {
			ctx.ui.notify("Cancelled", "info");
			return;
		}

		if (ctx.isIdle()) {
			pi.sendUserMessage(answers);
		} else {
			pi.sendUserMessage(answers, { deliverAs: "followUp" });
			ctx.ui.notify("Answers queued", "info");
		}
	};

	pi.registerCommand("answer", {
		description: "Extract questions from the last assistant message into interactive Q&A",
		handler: async (_args: string, ctx: ExtensionCommandContext) => answerHandler(ctx),
	});

	pi.registerShortcut("ctrl+.", {
		description: "Extract and answer questions",
		handler: answerHandler,
	});
}
