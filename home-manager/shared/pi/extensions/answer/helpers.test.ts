import test from "node:test";
import assert from "node:assert/strict";

import {
	buildAnswerMessage,
	findLastAssistantText,
	parseExtractionResponse,
	parseExtractionResult,
	prepareAssistantTextForExtraction,
	withResolvedModelBaseUrl,
} from "./helpers.ts";

test("parseExtractionResult accepts plain JSON, fenced JSON, and prose-wrapped JSON", () => {
	assert.deepEqual(parseExtractionResult('{"questions":[{"question":"Use SQLite?"}]}'), {
		questions: [{ question: "Use SQLite?" }],
	});

	assert.deepEqual(
		parseExtractionResult("```json\n{\n  \"questions\": [{\"question\": \"Need auth?\", \"context\": \"OAuth is already wired\"}]\n}\n```"),
		{
			questions: [
				{ question: "Need auth?", context: "OAuth is already wired" },
			],
		},
	);

	assert.deepEqual(
		parseExtractionResult([
			"Here are the questions I found:",
			'{"questions":[{"question":"Preferred shell?","context":"nushell or bash"}]}',
		].join("\n")),
		{
			questions: [{ question: "Preferred shell?", context: "nushell or bash" }],
		},
	);
});

test("parseExtractionResult rejects invalid payloads and normalizes blanks", () => {
	assert.equal(parseExtractionResult("not json"), null);
	assert.equal(parseExtractionResult('{"questions":"nope"}'), null);

	assert.deepEqual(
		parseExtractionResult(
			JSON.stringify({
				questions: [
					{ question: "  Preferred shell?  ", context: "  nushell or bash  " },
					{ question: "   " },
					{},
				],
			}),
		),
		{
			questions: [
				{ question: "Preferred shell?", context: "nushell or bash" },
			],
		},
	);
});

test("withResolvedModelBaseUrl applies provider-auth endpoint overrides", () => {
	const model = {
		id: "gpt-5.4-mini",
		baseUrl: "https://api.individual.githubcopilot.com",
	};

	assert.deepEqual(
		withResolvedModelBaseUrl(model, "https://api.enterprise.githubcopilot.com"),
		{
			id: "gpt-5.4-mini",
			baseUrl: "https://api.enterprise.githubcopilot.com",
		},
	);
	assert.equal(withResolvedModelBaseUrl(model, undefined), model);
	assert.equal(withResolvedModelBaseUrl(model, model.baseUrl), model);
});

test("parseExtractionResponse preserves provider failures and unexpected stops", () => {
	assert.deepEqual(
		parseExtractionResponse({
			stopReason: "error",
			errorMessage: "OpenAI API error (421): Misdirected Request",
			content: [],
		}),
		{
			status: "error",
			message: "OpenAI API error (421): Misdirected Request",
		},
	);
	assert.deepEqual(
		parseExtractionResponse({ stopReason: "length", content: [] }),
		{
			status: "error",
			message: "Question extraction stopped unexpectedly (length)",
		},
	);
	assert.deepEqual(
		parseExtractionResponse({ stopReason: "aborted", content: [] }),
		{ status: "cancelled" },
	);
});

test("parseExtractionResponse parses successful text content", () => {
	assert.deepEqual(
		parseExtractionResponse({
			stopReason: "stop",
			content: [
				{ type: "thinking" },
				{ type: "text", text: '{"questions":[{"question":"Use SQLite?"}]}' },
			],
		}),
		{
			status: "success",
			value: { questions: [{ question: "Use SQLite?" }] },
		},
	);
	assert.deepEqual(
		parseExtractionResponse({
			stopReason: "stop",
			content: [{ type: "text", text: "not json" }],
		}),
		{
			status: "error",
			message: "Question extraction returned invalid JSON",
		},
	);
});

test("prepareAssistantTextForExtraction trims oversized assistant messages", () => {
	assert.equal(prepareAssistantTextForExtraction("  short answer  ", 40), "short answer");

	const prepared = prepareAssistantTextForExtraction("A".repeat(10) + "B".repeat(30), 20);
	assert.match(prepared, /Truncated assistant message/);
	assert.match(prepared, /B{20}$/);
});

test("buildAnswerMessage separates quoted context from the answer", () => {
	assert.equal(
		buildAnswerMessage(
			[{ question: "What’s the difference?", context: "Compare NixOS with traditional Linux distros." }],
			["NixOS is deterministic and not mutable like traditional Linux distributions."],
		),
		[
			"I answered your questions in the following way:",
			"",
			"Q: What’s the difference?",
			"> Compare NixOS with traditional Linux distros.",
			"",
			"A: NixOS is deterministic and not mutable like traditional Linux distributions.",
		].join("\n"),
	);
});

test("findLastAssistantText returns the latest complete assistant text", () => {
	const result = findLastAssistantText([
		{
			type: "message",
			message: {
				role: "assistant",
				stopReason: "stop",
				content: [{ type: "text", text: "Earlier answer" }],
			},
		},
		{
			type: "message",
			message: {
				role: "assistant",
				stopReason: "stop",
				content: [{ type: "text", text: "Latest answer" }],
			},
		},
	]);

	assert.deepEqual(result, { text: "Latest answer" });
});

test("findLastAssistantText reports incomplete or missing assistant messages", () => {
	assert.deepEqual(
		findLastAssistantText([
			{
				type: "message",
				message: {
					role: "assistant",
					stopReason: "tool_use",
					content: [{ type: "text", text: "Partial" }],
				},
			},
		]),
		{ error: "Last assistant message incomplete (tool_use)" },
	);

	assert.deepEqual(findLastAssistantText([]), {
		error: "No assistant messages found",
	});
});
