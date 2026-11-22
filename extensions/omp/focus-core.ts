export type Role = "user" | "assistant";

export type EntryLike = {
	type: string;
	id: string;
	message?: { role?: string; content?: unknown; attribution?: string };
};

export type Turn = { id: string; role: Role; text: string };

export function textOf(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const block of content) {
		if (block && typeof block === "object" && (block as { type?: unknown }).type === "text") {
			const text = (block as { text?: unknown }).text;
			if (typeof text === "string") parts.push(text);
		}
	}
	return parts.join("\n");
}

function turnOf(entry: EntryLike | undefined): Turn | undefined {
	if (!entry || entry.type !== "message") return undefined;
	const role = entry.message?.role;
	if (role !== "user" && role !== "assistant") return undefined;
	if (role === "user" && entry.message?.attribution === "agent") return undefined;
	const text = textOf(entry.message?.content);
	return text.trim() === "" ? undefined : { id: entry.id, role, text };
}

export function lastTurn(branch: readonly EntryLike[], role: Role): Turn | undefined {
	for (let at = branch.length - 1; at >= 0; at--) {
		const turn = turnOf(branch[at]);
		if (turn?.role === role) return turn;
	}
	return undefined;
}

export function turnsOf(branch: readonly EntryLike[]): Turn[] {
	const turns: Turn[] = [];
	for (const entry of branch) {
		const turn = turnOf(entry);
		if (turn) turns.push(turn);
	}
	return turns;
}

export type Action = Role | "pick";

export function actionFor(args: string): Action | undefined {
	const word = args.trim().toLowerCase();
	if (word === "" || word === "reply" || word === "assistant") return "assistant";
	if (word === "prompt" || word === "user") return "user";
	if (word === "pick") return "pick";
	return undefined;
}

export type PickList = { labels: string[]; turns: Turn[]; checked: number[] };

export function pickList(turns: readonly Turn[], tagged: ReadonlySet<string>, width = 72): PickList {
	const list: PickList = { labels: [], turns: [], checked: [] };
	for (let at = turns.length - 1; at >= 0; at--) {
		const turn = turns[at]!;
		const words = turn.text.replace(/\s+/g, " ").trim();
		const snippet = words.length > width ? `${words.slice(0, width - 1)}…` : words;
		if (tagged.has(turn.id)) list.checked.push(list.labels.length);
		list.labels.push(`${at + 1}. ${turn.role === "user" ? "you" : "reply"}: ${snippet}`);
		list.turns.push(turn);
	}
	return list;
}

export function taggedIds(tagsText: string, session: string): Set<string> {
	const ids = new Set<string>();
	for (const line of tagsText.split("\n")) {
		if (line.trim() === "") continue;
		try {
			const tag: unknown = JSON.parse(line);
			if (tag && typeof tag === "object" && "session" in tag && "uuid" in tag && tag.session === session && typeof tag.uuid === "string") ids.add(tag.uuid);
		} catch {
		}
	}
	return ids;
}

export const WRITER_CAP = 2000;

export function tagArgv(turn: Turn, session: { id: string; cwd: string; file: string | undefined }, cap = WRITER_CAP + 1): string[] {
	return [
		"tag",
		"--harness",
		"omp",
		"--session",
		session.id,
		"--uuid",
		turn.id,
		"--role",
		turn.role,
		"--cwd",
		session.cwd,
		...(session.file ? ["--transcript", session.file] : []),
		"--text",
		cutAt(turn.text, cap),
	];
}

export function cutAt(text: string, cap: number): string {
	const chars = Array.from(text);
	return chars.length > cap ? chars.slice(0, cap).join("") : text;
}

export function cliPath(env: Record<string, string | undefined>, home: string): string {
	if (env.AUTODREAM_FOCUS_BIN) return env.AUTODREAM_FOCUS_BIN;
	return `${env.AUTODREAM_DIR || `${home}/.claude/autodream`}/autodream-focus.sh`;
}

export function tagsPath(env: Record<string, string | undefined>, home: string, cliDir: string, isInstallDir: (dir: string) => boolean): string {
	if (env.AUTODREAM_TAGS_FILE) return env.AUTODREAM_TAGS_FILE;
	const dir = env.AUTODREAM_DIR || (isInstallDir(cliDir) ? cliDir : `${home}/.claude/autodream`);
	return `${dir}/tags.jsonl`;
}
