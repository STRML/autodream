/**
 * autodream-focus for OMP: tag a turn so the nightly autodream run takes a close look at it.
 *
 *   /focus          tag your last reply
 *   /focus prompt   tag the last thing you typed
 *   /focus pick     pick any prompt or reply on this branch (checked rows are already tagged)
 *   ctrl+shift+f    the same as /focus (AUTODREAM_FOCUS_KEY changes it; set it empty to have none)
 *
 * Running it again on the same turn takes the tag back. For a turn in an older session, /resume it and /focus pick.
 * OMP draws its own prompt and reply rows and gives an extension no way to put a button on them (only its own custom
 * messages, the footer and widgets), so this is a command, as close to the Claude Code button as OMP allows. It does
 * none of the writing: bin/autodream-focus.sh does, so the lock, the unreadable-file refusal and the line format are
 * the same for every harness. The picker only reads tags.jsonl, to mark what is tagged.
 *
 * Install (opt-in; autodream's install.sh does not touch it):
 *   ln -s /path/to/cc-autodream/extensions/omp/autodream-focus.ts ~/.omp/agent/extensions/autodream-focus.ts
 * The shared command is found at $AUTODREAM_DIR/autodream-focus.sh (default ~/.claude/autodream/), which install.sh
 * links; AUTODREAM_FOCUS_BIN names another.
 */
import type { ExtensionAPI, ExtensionContext } from "@oh-my-pi/pi-coding-agent";
import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { actionFor, cliPath, lastTurn, pickList, tagArgv, taggedIds, tagsPath, turnsOf, type Turn } from "./focus-core";

const STATUS = "autodream-focus";

function isFile(path: string): boolean {
	try {
		return statSync(path).isFile();
	} catch {
		return false;
	}
}

/** What this session has tagged. A tags file that is missing or will not read marks nothing; the script still refuses to write over an unreadable one. */
function readTagged(path: string, session: string): Set<string> {
	try {
		return taggedIds(readFileSync(path, "utf8"), session);
	} catch {
		return new Set();
	}
}

export default function autodreamFocus(pi: ExtensionAPI) {
	const cli = cliPath(process.env, homedir());
	const tags = tagsPath(process.env, homedir(), dirname(cli), dir => isFile(join(dir, "config")) || isFile(join(dir, "PROMPT.md")));

	async function toggle(turn: Turn, ctx: ExtensionContext): Promise<void> {
		const result = await pi.exec(
			cli,
			tagArgv(turn, {
				id: ctx.sessionManager.getSessionId(),
				cwd: ctx.cwd,
				file: ctx.sessionManager.getSessionFile(),
			}),
			{ timeout: 10_000 },
		);
		if (result.code !== 0) {
			ctx.ui.notify(`autodream focus: ${(result.stderr || result.stdout || `exit ${result.code}`).trim()}`, "error");
			return;
		}
		const isTagged = result.stdout.trimStart().startsWith("tagged ");
		ctx.ui.setStatus(STATUS, isTagged ? "✓ autodream focus" : undefined);
		ctx.ui.notify(
			isTagged ? "Tagged: tonight's autodream takes a close look at this." : "Tag removed.",
			"info",
		);
	}

	async function pick(ctx: ExtensionContext): Promise<void> {
		const turns = turnsOf(ctx.sessionManager.getBranch());
		if (turns.length === 0) {
			ctx.ui.notify("autodream focus: no prompt or reply with text on this branch yet.", "warning");
			return;
		}
		const list = pickList(turns, readTagged(tags, ctx.sessionManager.getSessionId()));
		const choice = await ctx.ui.select("autodream focus: tag a turn", list.labels, {
			selectionMarker: "checkbox",
			checkedIndices: list.checked,
			helpText: "checked = tagged · Enter tags or untags · Esc closes",
		});
		const turn = choice === undefined ? undefined : list.turns[list.labels.indexOf(choice)];
		if (turn) await toggle(turn, ctx);
	}

	async function focus(args: string, ctx: ExtensionContext): Promise<void> {
		const action = actionFor(args);
		if (!action) {
			ctx.ui.notify("autodream focus: /focus tags your last reply, /focus prompt your last prompt, /focus pick any turn.", "warning");
			return;
		}
		if (action === "pick") return pick(ctx);
		const turn = lastTurn(ctx.sessionManager.getBranch(), action);
		if (!turn) {
			ctx.ui.notify(`autodream focus: no ${action === "user" ? "prompt" : "reply"} with text on this branch yet.`, "warning");
			return;
		}
		await toggle(turn, ctx);
	}

	pi.registerCommand("focus", {
		description: "Tag your last reply (/focus prompt: your last prompt, /focus pick: any turn) for tonight's autodream",
		handler: (args, ctx) => focus(args, ctx),
	});

	// Not ctrl+alt+f: ctrl+option chords are the usual macOS window-manager family, and on the first live run one
	// moved the window instead of reaching OMP. Neither OMP nor cmux binds ctrl+shift+f, and Ghostty passes it through.
	const key = process.env.AUTODREAM_FOCUS_KEY ?? "ctrl+shift+f";
	if (key !== "") {
		pi.registerShortcut(key as Parameters<ExtensionAPI["registerShortcut"]>[0], {
			description: "Tag your last reply for tonight's autodream",
			handler: ctx => focus("", ctx),
		});
	}

	// The footer mark describes the reply that was tagged; a new run of the agent makes it a different one.
	pi.on("agent_start", (_event, ctx) => ctx.ui.setStatus(STATUS, undefined));
}
