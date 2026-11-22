# runsh: A finished report needs the open-questions marker, not just a non-empty file

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_finishes_date`)

## Context
The idempotency guard (#111) used to test only `-s "$REPORT_PATH"`. A half-written report (a run killed mid-write, or an older runner's partial) read as done: every later trigger no-opped, and question-streaks cleared the board over it.

## Decision
`report_finishes_date` returns success when the report is non-empty and `report_complete` holds (`report_finishes`: the open-questions marker is present and, for dates on or after `AUTODREAM_QUESTIONS_EPOCH`, so is the questions block). A report for a date before `AUTODREAM_MARKER_EPOCH` (default `2026-08-19`) predates the marker and counts as finished. `unassembled_dates()` makes the same exemption, so the two agree about whether a date is finished. Unmarked reports under the epoch are named in the log line `note: unmarked reports predating AUTODREAM_MARKER_EPOCH (treated as complete)` and under their own key in `unassembled_dates`, so the exemption is visible. The exemption is a date and not a heuristic because a non-empty unmarked report is either legacy or a truncated capture, and only the date the contract began separates them; the scan window (`AUTODREAM_UNASSEMBLED_WINDOW`, 7 days) bounds the damage of a wrong epoch, and the epoch is the thing to set when backfilling older dates.

See CLAUDE.md, "Sleep resilience" (idempotency guard).

## Consequences
The default `2026-08-19` is written in three places (the knob documentation in `docs/run-knobs.md`, `report_finishes_date`, `unassembled_dates`): change all three together or the guard and the sweep disagree. A marker-less report on or after the epoch is moved aside as `.stale-<epoch>` before L2 and rebuilt; the copy is kept if the rebuild fails and discarded once a complete report replaces it. See `finished-run-requires-end-marker` for why a non-empty file is not proof of completion.
