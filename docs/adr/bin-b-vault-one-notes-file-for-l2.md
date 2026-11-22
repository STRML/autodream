# bin-b: every capture surface is merged into one operator-notes.md, and the prompt reads only that

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`collect`)

## Context

`autodream-note.sh` appends to `$AUTODREAM_DIR/notes.md`, which works only from a terminal on this Mac. Notes worth leaving for the nightly run mostly come up away from the terminal: on a phone, mid-meeting, in bed. An Obsidian vault folder syncs to the phone and takes a note from anything that can write a file (Obsidian mobile, Shortcuts, Drafts, a share sheet).

CLAUDE.md, "Operator notes: one file for the prompt, many surfaces for the human", records the same design.

## Decision

- `collect` writes `findings/<date>/operator-notes.md` from every surface, and `PROMPT.md` reads that one path. A new surface is a change to this script and never to the prompt.
- The `notes.md` surface is passed through verbatim. Its `- [added] (expires DATE) text` lines are the format `PROMPT.md` already parses, and expiry filtering for them stays in the prompt.
- Every step is best-effort. A missing vault, an unreadable file or a failed move is reported in the output and never aborts the caller, because no note is worth losing a night's report over.

## Consequences

The two surfaces use different expiry mechanisms (see `bin-b-vault-expiry-judged-at-report-date.md`). A new surface also needs a line in the file's header counts (`active`, `unreadable`, ...), since `PROMPT.md` skips the section when `active` is 0.
