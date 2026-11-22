# rest: the OMP focus extension is a command that gathers a turn and hands it to the shared writer

Status: accepted · Date: 2026-11-21 · Code: `extensions/omp/autodream-focus.ts` (`tagsFileNow`, `toggle`, the shortcut and `agent_start` hooks), `extensions/omp/focus-core.ts` (`turnOf`, `tagArgv`, `cutAt`, `WRITER_CAP`, `tagsPath`, `taggedIds`, `pickList`), `extensions/omp/autodream-focus.test.ts`

## Context

OMP draws its own prompt and reply rows and gives an extension no way to put a button on them (only its own custom messages, the footer and widgets). So the extension is a `/focus` command, as close to the Claude Code button as OMP allows. CLAUDE.md, "The focus mod", records why OMP and Codex tag through `bin/autodream-focus.sh` and not a copy of the mod's code, and `extensions/omp/README.md` has the setup.

Facts that shaped the code:

- The tags file has several writers. The script holds the lock, the unreadable-file refusal and the line format, so the extension does none of the writing (`docs/adr/rest-autodream-focus-kernel-flock.md`, `docs/adr/rest-autodream-focus-refuse-unreadable-and-append-adds.md`).
- The script also reads `$AUTODREAM_DIR/config`, which the extension cannot, so a tags file named only there is invisible to the extension's own resolution.
- OMP's `exec` has no stdin, so the turn text goes as an argument and a very long turn is bounded in the extension.
- The writer marks a cut with an ellipsis only when it sees more than its cap (2,000), counted in code points. A cut at exactly the cap would hand it a text that looks whole, and a cut in UTF-16 units splits an emoji. Same rule as `docs/adr/bin-b-mods-focus-writer-text-cap.md`.
- A user-role message attributed to the agent (a steering note, hook output, an advisor's prompt) is not something the person typed.
- On the first live run `ctrl+alt+f` moved the window instead of reaching OMP: ctrl+option chords are the usual macOS window-manager family. Neither OMP nor cmux binds `ctrl+shift+f`, and Ghostty passes it through.
- `bun test` cannot start a headless OMP from the Claude Code sandbox, because OMP registers a client under `~/.omp/run/daemons/`, the live daemon's state.

## Decision

- `focus-core.ts` holds what decides something, free of the OMP API so `bun test` runs it: reading a turn (text blocks only, joined; a bare string for a user message; thinking and tool-call blocks are not text; a reply with no text is not a turn; agent-attributed user turns are skipped, as the script's `last --harness omp` skips them), the `/focus` argument words, the picker rows, and the argv.
- `tagArgv` cuts the text at `WRITER_CAP + 1` code points (`cutAt`) so the writer sees a turn over its cap and marks the cut.
- The picker's labels lead with the turn's number counted from the oldest, because the select dialog hands back a label and this keeps two turns with the same words apart. Rows already tagged are checked.
- `taggedIds` reads `tags.jsonl` text and ignores a line it cannot parse (torn or hand-edited): the script keeps such a line, the picker just cannot mark it.
- `tagsFileNow` asks `<script> path` (5 s timeout) and falls back to `tagsPath`, which resolves the way the script does: `AUTODREAM_TAGS_FILE`, else `AUTODREAM_DIR`, else the script's own directory when it holds `config` or `PROMPT.md`, else `~/.claude/autodream`.
- The footer mark describes the reply that was tagged, so a new `agent_start` clears it.
- The shortcut defaults to `ctrl+shift+f`; `AUTODREAM_FOCUS_KEY` changes it and an empty value registers none.
- `autodream-focus.test.ts` runs the extension against a fake OMP API whose `exec` runs the real `bin/autodream-focus.sh`, so the whole path from `/focus` to the line in `tags.jsonl` is checked.

## Consequences

Unverified: OMP's own extension loader and key handling. The first run in a real OMP is the check. If the writer's cap or its line format changes, change `WRITER_CAP` and the argv here in the same commit. Do not give the extension a write path to `tags.jsonl`.
