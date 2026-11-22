# bin-b: the focus mod only reads tags.jsonl; every write goes through autodream-focus.sh

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/focus-lib.ts` (`focusScript`, `readTags`), `mods/autodream-focus/hooks/register.tsx` (`load`, `press`), `mods/autodream-focus/tests/focus.test.tsx` (`world`)

## Context

Three harnesses write `tags.jsonl`. The mod once rewrote the file itself, and `$.fs.write` is not an atomic rename and cannot take the script's flock, so a button press and an OMP or Codex tag could overwrite each other. CLAUDE.md "The focus mod" records this, and the rule that a read that fails must never lead to a write.

## Decision

- `focusScript` finds the writer (`AUTODREAM_FOCUS_BIN`, else the install dir). `press` runs it with `tag --harness claude ...`; the writer toggles, and the mod reads its stdout (`untagged ...` or `tagged ...`) to word the toast.
- `load` reads the file only. A file that is absent is empty. One that exists and will not read (over the 4 MiB a read allows, permissions, I/O error) throws, and `refresh` toasts that no turn shows as tagged instead of showing every turn as untagged.
- `readTags` skips a line it cannot parse (torn, hand-edited, from a later version); the writer leaves such lines on disk.
- The test stand-in toggles a line by id the way the writer does, and its `fs.write` handler records and denies every write, so a test fails if the mod ever writes.

## Consequences

A new field the writer adds is ignored by the mod. Do not add an `fs.write` path here without the script's lock.
