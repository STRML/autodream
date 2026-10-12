import { describe, expect, test } from "bun:test";
import { actionFor, cliPath, lastTurn, pickList, tagArgv, taggedIds, tagsPath, textOf, turnsOf, type EntryLike } from "./focus-core";

const msg = (id: string, role: string, content: unknown): EntryLike => ({ type: "message", id, message: { role, content } });

describe("textOf", () => {
	test("joins text blocks and ignores thinking and tool calls", () => {
		expect(textOf([{ type: "thinking", thinking: "hm" }, { type: "text", text: "a" }, { type: "toolCall" }, { type: "text", text: "b" }])).toBe("a\nb");
	});
	test("reads a bare string, the shape of a typed prompt", () => {
		expect(textOf("typed")).toBe("typed");
	});
	test("is empty for anything else", () => {
		expect(textOf(undefined)).toBe("");
		expect(textOf({ type: "text", text: "not an array" })).toBe("");
		expect(textOf([{ type: "text", text: 7 }])).toBe("");
	});
});

describe("lastTurn", () => {
	const branch: EntryLike[] = [
		msg("u1", "user", "first prompt"),
		msg("a1", "assistant", [{ type: "text", text: "first reply" }]),
		msg("u2", "user", "second prompt"),
		msg("a2", "assistant", [{ type: "text", text: "second reply" }]),
		msg("a3", "assistant", [{ type: "thinking", thinking: "only thoughts" }, { type: "toolCall" }]),
		{ type: "compaction", id: "c1" },
		msg("t1", "toolResult", [{ type: "text", text: "tool output" }]),
	];

	test("the last reply with text, skipping a turn that was only thinking and tool calls", () => {
		expect(lastTurn(branch, "assistant")).toEqual({ id: "a2", role: "assistant", text: "second reply" });
	});
	test("the last prompt", () => {
		expect(lastTurn(branch, "user")).toEqual({ id: "u2", role: "user", text: "second prompt" });
	});
	test("nothing on an empty branch, or one with no turn of that role", () => {
		expect(lastTurn([], "assistant")).toBeUndefined();
		expect(lastTurn([msg("u1", "user", "hi")], "assistant")).toBeUndefined();
	});
	test("a whitespace-only turn is not a turn to tag", () => {
		expect(lastTurn([msg("a1", "assistant", [{ type: "text", text: "  \n " }])], "assistant")).toBeUndefined();
	});
});

describe("actionFor", () => {
	test("no argument is the last reply", () => {
		expect(actionFor("")).toBe("assistant");
		expect(actionFor("  ")).toBe("assistant");
		expect(actionFor("reply")).toBe("assistant");
	});
	test("prompt or user is the last prompt, whatever the case", () => {
		expect(actionFor("prompt")).toBe("user");
		expect(actionFor(" USER ")).toBe("user");
	});
	test("pick opens the picker, whatever the case", () => {
		expect(actionFor("pick")).toBe("pick");
		expect(actionFor(" Pick ")).toBe("pick");
	});
	test("anything else is refused rather than guessed at", () => {
		expect(actionFor("the third one")).toBeUndefined();
	});
});

describe("turnsOf", () => {
	test("every prompt and reply with text, root to leaf, nothing else", () => {
		const branch: EntryLike[] = [
			msg("u1", "user", "first prompt"),
			msg("a1", "assistant", [{ type: "thinking", thinking: "hm" }, { type: "toolCall" }]),
			msg("t1", "toolResult", [{ type: "text", text: "tool output" }]),
			{ type: "compaction", id: "c1" },
			msg("a2", "assistant", [{ type: "text", text: "first reply" }]),
			msg("u2", "user", "  "),
			msg("u3", "user", "second prompt"),
		];
		expect(turnsOf(branch)).toEqual([
			{ id: "u1", role: "user", text: "first prompt" },
			{ id: "a2", role: "assistant", text: "first reply" },
			{ id: "u3", role: "user", text: "second prompt" },
		]);
	});
});

describe("pickList", () => {
	const turns = [
		{ id: "u1", role: "user" as const, text: "same words" },
		{ id: "a1", role: "assistant" as const, text: "same words" },
		{ id: "u2", role: "user" as const, text: "why is\n\n  the build   red?" },
	];

	test("newest first, numbered from the oldest, so two turns with the same words still differ", () => {
		const list = pickList(turns, new Set());
		expect(list.labels).toEqual(["3. you: why is the build red?", "2. reply: same words", "1. you: same words"]);
		expect(list.turns.map(t => t.id)).toEqual(["u2", "a1", "u1"]);
	});
	test("marks the turns already tagged, by their place in the list", () => {
		expect(pickList(turns, new Set(["u1", "u2"])).checked).toEqual([0, 2]);
	});
	test("cuts a long turn to the width, with an ellipsis", () => {
		const [label] = pickList([{ id: "a1", role: "assistant", text: "x".repeat(500) }], new Set(), 20).labels;
		expect(label).toBe(`1. reply: ${"x".repeat(19)}…`);
	});
});

describe("taggedIds", () => {
	test("the rows tagged in this session, skipping other sessions and lines it cannot read", () => {
		const file = [
			JSON.stringify({ id: "s1:a1", session: "s1", uuid: "a1" }),
			JSON.stringify({ id: "s2:a9", session: "s2", uuid: "a9" }),
			"{torn",
			JSON.stringify({ session: "s1", uuid: 7 }),
			JSON.stringify({ id: "s1:u1", session: "s1", uuid: "u1" }),
			"",
		].join("\n");
		expect([...taggedIds(file, "s1")]).toEqual(["a1", "u1"]);
	});
});

describe("tagsPath", () => {
	const never = () => false;
	test("AUTODREAM_TAGS_FILE wins, as it does in the script", () => {
		expect(tagsPath({ AUTODREAM_TAGS_FILE: "/t.jsonl", AUTODREAM_DIR: "/opt/ad" }, "/Users/x", "/bin", never)).toBe("/t.jsonl");
	});
	test("then AUTODREAM_DIR", () => {
		expect(tagsPath({ AUTODREAM_DIR: "/opt/ad" }, "/Users/x", "/bin", never)).toBe("/opt/ad/tags.jsonl");
	});
	test("then the script's own directory when it is an install, else the default install", () => {
		expect(tagsPath({}, "/Users/x", "/inst", dir => dir === "/inst")).toBe("/inst/tags.jsonl");
		expect(tagsPath({}, "/Users/x", "/repo/bin", never)).toBe("/Users/x/.claude/autodream/tags.jsonl");
	});
});

describe("tagArgv", () => {
	const turn = { id: "r1", role: "assistant" as const, text: "the reply" };

	test("names the harness, session, row, speaker, cwd, transcript and text", () => {
		expect(tagArgv(turn, { id: "s1", cwd: "/x", file: "/x/s1.jsonl" })).toEqual([
			"tag", "--harness", "omp", "--session", "s1", "--uuid", "r1", "--role", "assistant",
			"--cwd", "/x", "--transcript", "/x/s1.jsonl", "--text", "the reply",
		]);
	});
	test("leaves out a transcript the session has not written yet", () => {
		expect(tagArgv(turn, { id: "s1", cwd: "/x", file: undefined })).not.toContain("--transcript");
	});
	test("caps the text it passes", () => {
		const argv = tagArgv({ ...turn, text: "y".repeat(5000) }, { id: "s1", cwd: "/x", file: undefined }, 100);
		expect(argv[argv.length - 1]).toHaveLength(100);
	});
});

describe("cliPath", () => {
	test("defaults to the install directory autodream links its scripts into", () => {
		expect(cliPath({}, "/Users/x")).toBe("/Users/x/.claude/autodream/autodream-focus.sh");
	});
	test("AUTODREAM_DIR moves it, and an empty one counts as unset", () => {
		expect(cliPath({ AUTODREAM_DIR: "/opt/ad" }, "/Users/x")).toBe("/opt/ad/autodream-focus.sh");
		expect(cliPath({ AUTODREAM_DIR: "" }, "/Users/x")).toBe("/Users/x/.claude/autodream/autodream-focus.sh");
	});
	test("AUTODREAM_FOCUS_BIN wins", () => {
		expect(cliPath({ AUTODREAM_FOCUS_BIN: "/bin/f", AUTODREAM_DIR: "/opt/ad" }, "/Users/x")).toBe("/bin/f");
	});
});
