# rest: `last` finds the directory's newest session without a count limit and reads only a person's live turn

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`newest_session`, `cmd_last`)

## Context

Neither OMP nor Codex can draw a button, so `last` is what a person runs from a second terminal. Things learned building it, each fixed after a review or a live run:

- `last` read sessions newest first with a count limit across the whole root, which hid a recent session of the asked directory behind other directories' newer ones.
- A Codex user turn is its own record: an `item_completed` UserMessage event (older builds: an `event_msg` user_message). The `response_item` messages with role user are what Codex injects (instructions, environment context), whatever their text starts with. In the 30 days measured, Codex had 11 interactive sessions against 396 headless `codex exec` runs, so it was scoped by usage and there is no Codex adapter.
- An OMP session file is an append-only tree that keeps every branch the user backed out of. Reading the raw file credits the user with abandoned branches.
- An OMP user-role message with `attribution` of `agent` (steering, hook output, an advisor's prompt stream) is not a human turn. A message with no attribution field counts, as in files from before the field.

## Decision

- `newest_session` sorts the harness's session files by mtime (newest first, within the last 14 days, found by `find -mtime -14`) and reads them until one records the wanted directory (the given path or its physical `pwd -P`). There is no count limit before that match; the 14-day window is the bound.
- Codex: the assistant turn is a `response_item` message with role assistant; the user turn is only the `item_completed` UserMessage or `user_message` event.
- OMP: the file is run through `adapters/omp/linearize.sh` to the live chain; if it cannot be walked, `last` refuses rather than falling back to the raw file. The picked turn skips `attribution == "agent"`. The extension's TypeScript reader (`extensions/omp/focus-core.ts`, `turnOf`) skips agent turns the same way.

## Consequences

The scan can read many files when a directory has no recent session, which the 14-day window bounds. A new harness needs its own two branches here and in `cmd_last`. If Codex changes how it records a human turn, `last --role user` returns nothing or an injected message; test against a real rollout file.
