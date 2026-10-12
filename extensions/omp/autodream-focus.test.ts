import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { chmodSync, mkdtempSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import autodreamFocus from "./autodream-focus";

/**
 * The extension against a fake OMP API whose `exec` runs the REAL bin/autodream-focus.sh, so what is checked is the
 * whole path from `/focus` to the line in tags.jsonl. What it cannot check is OMP's own loader and key handling.
 */

const CLI = resolve(import.meta.dir, "../../bin/autodream-focus.sh");

const entry = (id: string, role: string, content: unknown) => ({ type: "message", id, message: { role, content } });
const BRANCH = [
	entry("u1", "user", "first prompt"),
	entry("a1", "assistant", [{ type: "text", text: "first reply" }]),
	entry("u2", "user", "why is the build red?"),
	entry("a2", "assistant", [{ type: "thinking", thinking: "hm" }, { type: "text", text: "The lockfile is stale.\nRun npm ci." }]),
	entry("a3", "assistant", [{ type: "toolCall" }]),
];

let dir: string;
let tags: string;
const saved = { ...process.env };

beforeEach(() => {
	dir = mkdtempSync(join(tmpdir(), "focus-omp-"));
	tags = join(dir, "tags.jsonl");
	process.env.AUTODREAM_DIR = dir;
	process.env.AUTODREAM_FOCUS_BIN = CLI;
	delete process.env.AUTODREAM_FOCUS_KEY;
});
afterEach(() => {
	try { chmodSync(tags, 0o644); } catch { /* not created */ }
	rmSync(dir, { recursive: true, force: true });
	process.env = { ...saved };
});

type Picked = { title: string; labels: string[]; checked: readonly number[] | undefined };

function rig(branch: unknown[] = BRANCH, choose: (labels: string[]) => string | undefined = () => undefined) {
	const commands = new Map<string, { handler: (args: string, ctx: unknown) => Promise<void> }>();
	const shortcuts = new Map<string, { handler: (ctx: unknown) => Promise<void> | void }>();
	const events = new Map<string, (event: unknown, ctx: unknown) => unknown>();
	const notes: [string, string | undefined][] = [];
	const statuses: [string, string | undefined][] = [];
	const execs: string[][] = [];
	const pickers: Picked[] = [];
	const pi = {
		registerCommand: (name: string, options: never) => commands.set(name, options),
		registerShortcut: (key: string, options: never) => shortcuts.set(key, options),
		on: (event: string, handler: never) => events.set(event, handler),
		exec: async (command: string, args: string[]) => {
			execs.push(args);
			const proc = Bun.spawn([command, ...args], { env: process.env, stdout: "pipe", stderr: "pipe" });
			const [stdout, stderr, code] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text(), proc.exited]);
			return { stdout, stderr, code };
		},
	};
	const ctx = {
		cwd: "/Users/x/proj",
		ui: {
			notify: (message: string, type?: string) => notes.push([message, type]),
			setStatus: (key: string, text: string | undefined) => statuses.push([key, text]),
			select: async (title: string, labels: string[], options?: { checkedIndices?: readonly number[] }) => {
				pickers.push({ title, labels, checked: options?.checkedIndices });
				return choose(labels);
			},
		},
		sessionManager: {
			getBranch: () => branch,
			getSessionId: () => "s1",
			getSessionFile: () => "/Users/x/.omp/agent/sessions/-x/s1.jsonl",
		},
	};
	autodreamFocus(pi as never);
	return { commands, shortcuts, events, notes, statuses, execs, pickers, ctx, run: (args = "") => commands.get("focus")!.handler(args, ctx) };
}

const lines = () => (existsSync(tags) ? readFileSync(tags, "utf8").split("\n").filter(Boolean).map(line => JSON.parse(line)) : []);

describe("/focus", () => {
	test("tags the last reply that has text, with the harness, session file and cwd", async () => {
		const { run, notes, statuses } = rig();
		await run();
		expect(lines()).toEqual([
			{
				id: "s1:a2",
				session: "s1",
				uuid: "a2",
				role: "assistant",
				text: "The lockfile is stale.\nRun npm ci.",
				cwd: "/Users/x/proj",
				taggedAt: expect.any(String),
				harness: "omp",
				transcript: "/Users/x/.omp/agent/sessions/-x/s1.jsonl",
			},
		]);
		expect(notes.at(-1)?.[0]).toContain("Tagged");
		expect(statuses.at(-1)).toEqual(["autodream-focus", "✓ autodream focus"]);
	});

	test("a second /focus on the same reply takes the tag back and clears the footer", async () => {
		const { run, notes, statuses } = rig();
		await run();
		await run();
		expect(lines()).toEqual([]);
		expect(notes.at(-1)?.[0]).toContain("removed");
		expect(statuses.at(-1)).toEqual(["autodream-focus", undefined]);
	});

	test("/focus prompt tags the last prompt as the user", async () => {
		const { run } = rig();
		await run("prompt");
		expect(lines().map(l => [l.uuid, l.role, l.text])).toEqual([["u2", "user", "why is the build red?"]]);
	});

	test("an argument it does not know is refused and nothing is run", async () => {
		const { run, notes, execs } = rig();
		await run("the third one");
		expect(execs).toEqual([]);
		expect(notes.at(-1)?.[1]).toBe("warning");
		expect(existsSync(tags)).toBe(false);
	});

	test("a branch with no reply yet says so", async () => {
		const { run, notes, execs } = rig([entry("u1", "user", "hello")]);
		await run();
		expect(execs).toEqual([]);
		expect(notes.at(-1)?.[0]).toContain("no reply");
	});

	test("a tags file that cannot be read is reported and left alone", async () => {
		const { run, notes, statuses } = rig();
		await Bun.write(tags, '{"note":"hand edit"}\n');
		chmodSync(tags, 0o000);
		await run();
		chmodSync(tags, 0o644);
		expect(notes.at(-1)?.[1]).toBe("error");
		expect(notes.at(-1)?.[0]).toContain("nothing was changed");
		expect(readFileSync(tags, "utf8")).toBe('{"note":"hand edit"}\n');
		expect(statuses).toEqual([]);
	});

	test("a missing shared command is an error, not a silent no-op", async () => {
		process.env.AUTODREAM_FOCUS_BIN = join(dir, "nope.sh");
		const { run, notes } = rig();
		await expect(run()).rejects.toBeDefined();
		expect(notes).toEqual([]);
	});
});

describe("/focus pick", () => {
	test("tags an earlier turn chosen in the picker, not the last one", async () => {
		const { run, pickers } = rig(BRANCH, labels => labels.find(label => label.includes("first prompt")));
		await run("pick");
		expect(pickers[0]?.labels).toEqual([
			"4. reply: The lockfile is stale. Run npm ci.",
			"3. you: why is the build red?",
			"2. reply: first reply",
			"1. you: first prompt",
		]);
		expect(lines().map(l => [l.uuid, l.role, l.text])).toEqual([["u1", "user", "first prompt"]]);
	});

	test("shows what is already tagged, and picking a tagged turn takes the tag back", async () => {
		const first = rig();
		await first.run();
		const { run, pickers, notes } = rig(BRANCH, labels => labels[0]);
		await run("pick");
		expect(pickers[0]?.checked).toEqual([0]);
		expect(lines()).toEqual([]);
		expect(notes.at(-1)?.[0]).toContain("removed");
	});

	test("closing the picker writes nothing", async () => {
		const { run, execs, pickers } = rig();
		await run("pick");
		expect(pickers).toHaveLength(1);
		expect(execs).toEqual([]);
		expect(existsSync(tags)).toBe(false);
	});

	test("a branch with nothing to tag says so instead of opening an empty picker", async () => {
		const { run, notes, pickers } = rig([entry("a1", "assistant", [{ type: "toolCall" }])]);
		await run("pick");
		expect(pickers).toEqual([]);
		expect(notes.at(-1)?.[1]).toBe("warning");
	});
});

describe("registration", () => {
	test("the shortcut is ctrl+shift+f by default (a window manager took ctrl+alt+f live) and runs the same thing", async () => {
		const { shortcuts, ctx } = rig();
		expect([...shortcuts.keys()]).toEqual(["ctrl+shift+f"]);
		await shortcuts.get("ctrl+shift+f")!.handler(ctx);
		expect(lines().map(l => l.uuid)).toEqual(["a2"]);
	});
	test("AUTODREAM_FOCUS_KEY moves it, and an empty one removes it", () => {
		process.env.AUTODREAM_FOCUS_KEY = "ctrl+shift+g";
		expect([...rig().shortcuts.keys()]).toEqual(["ctrl+shift+g"]);
		process.env.AUTODREAM_FOCUS_KEY = "";
		expect([...rig().shortcuts.keys()]).toEqual([]);
	});
	test("a new agent run clears the footer mark, which described the earlier reply", () => {
		const { events, statuses, ctx } = rig();
		events.get("agent_start")!({}, ctx);
		expect(statuses.at(-1)).toEqual(["autodream-focus", undefined]);
	});
});
