# runsh: A finished report needs the open-questions marker, not just a non-empty file

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_finishes_date`)

## Context
The idempotency guard (#111) used to test only `-s "$REPORT_PATH"`. A half-written report (a run killed mid-write, or an older runner's partial) read as done: every later trigger no-opped, and question-streaks cleared the board over it.

## Decision
`report_finishes_date` returns success when the report is non-empty and `report_complete` holds (the marker is present). A report for a date before `AUTODREAM_MARKER_EPOCH` (default `2026-08-19`) predates the marker and counts as finished. `unassembled_dates()` makes the same exemption, so the two cannot disagree about whether a date is finished.

See CLAUDE.md, "Sleep resilience" (idempotency guard).

## Consequences
Change the epoch exemption in one place only if you change it in `unassembled_dates()` too. A marker-less report is moved aside and rebuilt, not kept.
