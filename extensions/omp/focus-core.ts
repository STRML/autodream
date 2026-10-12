/**
 * The parts of the OMP focus extension that decide something, kept free of the OMP API so `bun test` can run them.
 * The extension (autodream-focus.ts) only gathers the session and calls the shared command.
 */

export type Role = "user" | "assistant";

/** What a session entry needs to expose for this to read it: OMP's `message` entries, as the JSONL holds them. */
export type EntryLike = {
	type: string;
	id: string;
	message?: { role?: string; content?: unknown };
};

export type Turn = { id: string; role: Role; text: string };

/** The text blocks of a message, joined. A user message may be a bare string; thinking and tool-call blocks are not text. */
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

/** The turn an entry holds, if it is a prompt or reply with text (a reply that was only thinking and tool calls is not). */
function turnOf(entry: EntryLike | undefined): Turn | undefined {
	if (!entry || entry.type !== "message") return undefined;
	const role = entry.message?.role;
	if (role !== "user" && role !== "assistant") return undefined;
	const text = textOf(entry.message?.content);
	return text.trim() === "" ? undefined : { id: entry.id, role, text };
}

/** The last turn by `role` on a branch ordered root to leaf. */
export function lastTurn(branch: readonly EntryLike[], role: Role): Turn | undefined {
	for (let at = branch.length - 1; at >= 0; at--) {
		const turn = turnOf(branch[at]);
		if (turn?.role === role) return turn;
	}
	return undefined;
}

/** Every prompt and reply with text on a branch, root to leaf: what `/focus pick` offers. */
export function turnsOf(branch: readonly EntryLike[]): Turn[] {
	const turns: Turn[] = [];
	for (const entry of branch) {
		const turn = turnOf(entry);
		if (turn) turns.push(turn);
	}
	return turns;
}

export type Action = Role | "pick";

/** `/focus` tags the last reply, `/focus prompt` (or `user`) the last thing you typed, `/focus pick` opens the picker. Anything else is refused. */
export function actionFor(args: string): Action | undefined {
	const word = args.trim().toLowerCase();
	if (word === "" || word === "reply" || word === "assistant") return "assistant";
	if (word === "prompt" || word === "user") return "user";
	if (word === "pick") return "pick";
	return undefined;
}

export type PickList = { labels: string[]; turns: Turn[]; checked: number[] };

/**
 * The picker's rows, newest first. The select dialog hands back a label, so each label leads with the turn's number
 * (counted from the oldest), which keeps two turns with the same words apart. `checked` are the rows already tagged.
 */
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

/** The row ids tagged in one session, from the text of tags.jsonl. A line it cannot read marks nothing. */
export function taggedIds(tagsText: string, session: string): Set<string> {
	const ids = new Set<string>();
	for (const line of tagsText.split("\n")) {
		if (line.trim() === "") continue;
		try {
			const tag: unknown = JSON.parse(line);
			if (tag && typeof tag === "object" && "session" in tag && "uuid" in tag && tag.session === session && typeof tag.uuid === "string") ids.add(tag.uuid);
		} catch {
			// A torn or hand-edited line: the script keeps it, the picker just cannot mark it.
		}
	}
	return ids;
}

/** The argv for `autodream-focus.sh tag`. The text goes as an argument because OMP's exec has no stdin. */
export function tagArgv(turn: Turn, session: { id: string; cwd: string; file: string | undefined }, cap = 2000): string[] {
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
		turn.text.length > cap ? turn.text.slice(0, cap) : turn.text,
	];
}

/** Where the shared command is: an explicit override, else the install directory autodream links its scripts into. */
export function cliPath(env: Record<string, string | undefined>, home: string): string {
	if (env.AUTODREAM_FOCUS_BIN) return env.AUTODREAM_FOCUS_BIN;
	return `${env.AUTODREAM_DIR || `${home}/.claude/autodream`}/autodream-focus.sh`;
}

/**
 * The tags file the script writes, resolved the way bin/autodream-focus.sh resolves it, so the picker marks what the
 * script will toggle: AUTODREAM_TAGS_FILE, else $AUTODREAM_DIR, else the script's own directory when it is an install
 * (holds `config` or `PROMPT.md`), else ~/.claude/autodream.
 */
export function tagsPath(env: Record<string, string | undefined>, home: string, cliDir: string, isInstallDir: (dir: string) => boolean): string {
	if (env.AUTODREAM_TAGS_FILE) return env.AUTODREAM_TAGS_FILE;
	const dir = env.AUTODREAM_DIR || (isInstallDir(cliDir) ? cliDir : `${home}/.claude/autodream`);
	return `${dir}/tags.jsonl`;
}
