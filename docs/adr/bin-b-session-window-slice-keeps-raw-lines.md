# bin-b: a day slice is the raw in-window lines, with the OMP meta header kept and one parentId nulled

Status: accepted · Date: 2026-11-21 · Code: `bin/session-window.sh` (`needs-slice`, `slice`, `TS_DEF`)

## Context

A transcript that spills outside the report day must be read as its day's records only, but the slimmer and the stats should see the bytes that were written. A linearized OMP chain links each entry to the one before by `parentId`, and `linearize.sh` refuses a parent with no entry behind it.

## Decision

- `needs-slice` is yes when any timestamped record lies outside the window, found with an early exit. The first-and-last-record shortcut assumes a chronological file, and one that is not would be read whole and leak other days in. A file wholly inside the day costs one full read, the same order as the stats pass.
- `slice` emits raw lines, not re-serialised. A torn line or a record with no clock is dropped: with a window set, a record that cannot be placed is not evidence for the day.
- `autodream_meta` stays in every slice. It names the session (cwd, advisor, nested) and the stats and project lookup read it.
- The first kept entry whose parent was cut is written with `parentId` null, so every `parentId` left resolves inside the slice. Nothing reads it after linearizing, but a closed chain cannot become a refusal in a later reader.
- The jq programs sit in single-quoted shell strings, so none may contain an apostrophe.

## Consequences

This is the one record that is not byte for byte. Normalize before cutting: cutting the raw OMP tree leaves dangling parents that `linearize.sh` refuses. See `bin-b-session-window-day-file-is-atomic.md` for the file the runner calls.
