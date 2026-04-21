import test from "node:test";
import assert from "node:assert/strict";
import Module from "node:module";
import type { SubagentTaskState } from "./types.ts";
import {
	buildReviewRepairPrompt,
	parseReviewOutput,
} from "./workflows/review/index.ts";

class MockSession {
	messages: Array<{ role?: string; content?: unknown }> = [];
	prompts: string[] = [];
	disposed = false;
	aborted = false;
	private listeners = new Set<(event: any) => void>();

	constructor(
		private readonly outputs: string[],
		private readonly options?: { emitDeltas?: boolean },
	) {}

	subscribe(listener: (event: any) => void) {
		this.listeners.add(listener);
		return () => this.listeners.delete(listener);
	}

	async prompt(input: string) {
		this.prompts.push(input);
		const assistantText = this.outputs[this.prompts.length - 1] ?? "";

		this.emit({ type: "message_start", message: { role: "assistant" } });
		if (this.options?.emitDeltas) {
			for (const chunk of chunkText(assistantText)) {
				this.emit({
					type: "message_update",
					assistantMessageEvent: { type: "text_delta", delta: chunk },
				});
			}
		}
		const message = {
			role: "assistant",
			content: assistantText,
			usage: { totalTokens: 42 },
		};
		this.messages.push(message);
		this.emit({ type: "message_end", message });
	}

	async abort() {
		this.aborted = true;
	}

	dispose() {
		this.disposed = true;
	}

	private emit(event: any) {
		for (const listener of this.listeners) listener(event);
	}
}

function chunkText(text: string): string[] {
	const chunks = text.match(/.{1,18}(?:\n|$)/g);
	return chunks && chunks.length > 0 ? chunks : [text];
}

function createReviewTaskState(): SubagentTaskState {
	return {
		workflow: "review",
		index: 0,
		taskId: "sub_now_test_task_1",
		task: "Review changes",
		label: "Opus 4.6",
		model: "github-copilot/claude-opus-4.6",
		thinkingLevel: "medium",
		cwd: "/tmp/project",
		metadata: { focus: "correctness and regressions" },
		state: "pending",
		toolUses: 0,
		turnCount: 0,
		tokenCount: 0,
		responseText: "",
		history: [],
		recentTools: [],
		recentOutputLines: [],
	};
}

async function withMockedCodingAgent<T>(
	run: (runSingleTask: typeof import("./runner.ts").runSingleTask) => Promise<T>,
): Promise<T> {
	const originalLoad = (Module as any)._load;
	(Module as any)._load = function (
		request: string,
		parent: unknown,
		isMain: boolean,
	) {
		if (request === "@mariozechner/pi-coding-agent") {
			return {
				createAgentSession: async () => {
					throw new Error("createAgentSession should not be called in this test");
				},
				DefaultResourceLoader: class {},
				getAgentDir: () => "/tmp/agent",
				SessionManager: { inMemory: () => ({}) },
				createBashTool: () => ({ execute: async () => undefined }),
				createFindTool: () => ({ execute: async () => undefined }),
				createGrepTool: () => ({ execute: async () => undefined }),
				createLsTool: () => ({ execute: async () => undefined }),
				createReadTool: () => ({ execute: async () => undefined }),
			};
		}
		return originalLoad.call(this, request, parent, isMain);
	};

	try {
		const { runSingleTask } = await import("./runner.ts");
		return await run(runSingleTask);
	} finally {
		(Module as any)._load = originalLoad;
	}
}

test("runSingleTask repairs malformed review output once and keeps repair metadata", async () => {
	await withMockedCodingAgent(async (runSingleTask) => {
		const taskState = createReviewTaskState();
		const session = new MockSession([
			[
				"Let me inspect the relevant files for context.",
				"",
				"<read_file>",
				"<path>home-manager/shared/pi/extensions/subagents/runner.ts</path>",
				"</read_file>",
			].join("\n"),
			[
				"## Summary",
				"Looks safe overall.",
				"",
				"## Verdict",
				"correct",
				"",
				"## Findings",
				"- None",
				"",
				"## Non-blocking Callouts",
				"- Dependency versions changed.",
				"",
				"## Next Steps",
				"- Add a regression test",
			].join("\n"),
		]);
		let updateCount = 0;

		const result = await runSingleTask(taskState, {
			parentCtx: {
				model: { provider: "github-copilot", id: "claude-opus-4.6" } as any,
			},
			emitRunUpdate: () => {
				updateCount += 1;
			},
			systemPrompt: "You are a code review subagent.",
			parseOutput: parseReviewOutput,
			buildRepairPrompt: buildReviewRepairPrompt,
			createSession: async () => session,
		});

		assert.equal(result.status, "success");
		assert.equal(result.summary, "Looks safe overall.");
		assert.equal(result.parseMeta?.structure, "valid");
		assert.deepEqual(result.data, {
			verdict: "correct",
			findings: [],
			humanReviewerCallouts: ["Dependency versions changed."],
			suggestedNextSteps: ["Add a regression test"],
		});
		assert.equal(session.prompts.length, 2);
		assert.match(session.prompts[1] ?? "", /Rewrite your final answer only\./);
		assert.match(session.prompts[1] ?? "", /## Non-blocking Callouts/);
		assert.equal(result.metadata?.focus, "correctness and regressions");
		assert.equal(result.metadata?.repairAttempted, true);
		assert.equal(result.metadata?.repairSucceeded, true);
		assert.equal(taskState.metadata?.repairAttempted, true);
		assert.equal(taskState.metadata?.repairSucceeded, true);
		assert.ok(
			taskState.history.some((entry) =>
				entry.text.includes("repairing malformed review output"),
			),
		);
		assert.ok(
			taskState.history.some((entry) =>
				entry.text.includes("review output repair succeeded"),
			),
		);
		assert.equal(session.disposed, true);
		assert.ok(updateCount > 0);
	});
});

test("runSingleTask keeps streaming repair output separate from the initial malformed response", async () => {
	await withMockedCodingAgent(async (runSingleTask) => {
		const invalidResponse = [
			"Let me inspect the relevant files for context.",
			"",
			"<read_file>",
			"<path>home-manager/shared/pi/extensions/subagents/runner.ts</path>",
			"</read_file>",
		].join("\n");
		const repairedResponse = [
			"## Summary",
			"Looks safe overall.",
			"",
			"## Verdict",
			"correct",
			"",
			"## Findings",
			"- None",
			"",
			"## Non-blocking Callouts",
			"- Dependency versions changed.",
			"",
			"## Next Steps",
			"- Add a regression test",
		].join("\n");
		const session = new MockSession([invalidResponse, repairedResponse], {
			emitDeltas: true,
		});
		const taskState = createReviewTaskState();
		const responseSnapshots: string[] = [];

		const result = await runSingleTask(taskState, {
			parentCtx: {
				model: { provider: "github-copilot", id: "claude-opus-4.6" } as any,
			},
			emitRunUpdate: () => {
				responseSnapshots.push(taskState.responseText);
			},
			systemPrompt: "You are a code review subagent.",
			parseOutput: parseReviewOutput,
			buildRepairPrompt: buildReviewRepairPrompt,
			createSession: async () => session,
		});

		assert.equal(result.rawResponse, repairedResponse);
		assert.doesNotMatch(result.rawResponse ?? "", /Let me inspect the relevant files/);
		assert.ok(
			responseSnapshots.some((snapshot) => snapshot.includes("## Summary")),
		);
		assert.ok(
			responseSnapshots.every(
				(snapshot) =>
					!(snapshot.includes("## Summary") && snapshot.includes("Let me inspect")),
			),
		);
	});
});
