import test from "node:test";
import assert from "node:assert/strict";

import {
	buildAnswerMessage,
	findLastAssistantText,
	parseExtractionResult,
} from "./helpers.ts";

test("parseExtractionResult accepts plain JSON and fenced JSON", () => {
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
