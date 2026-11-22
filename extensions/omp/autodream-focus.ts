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

	async function tagsFileNow(): Promise<string> {
		try {
			const result = await pi.exec(cli, ["path"], { timeout: 5_000 });
			const said = result.stdout.trim();
			if (result.code === 0 && said !== "") return said;
		} catch {
		}
		return tags;
	}

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
		const list = pickList(turns, readTagged(await tagsFileNow(), ctx.sessionManager.getSessionId()));
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

	const key = process.env.AUTODREAM_FOCUS_KEY ?? "ctrl+shift+f";
	if (key !== "") {
		pi.registerShortcut(key as Parameters<ExtensionAPI["registerShortcut"]>[0], {
			description: "Tag your last reply for tonight's autodream",
			handler: ctx => focus("", ctx),
		});
	}

	pi.on("agent_start", (_event, ctx) => ctx.ui.setStatus(STATUS, undefined));
}
