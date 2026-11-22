# tests-run-all: the marker-guard test sets AUTODREAM_MARKER_EPOCH to the fixture date

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_idempotency_guard_needs_a_complete_report`)

## Context

`report_finishes_date` in `bin/run.sh` treats a report as finished when it carries the open-questions marker, or when the target date is before `AUTODREAM_MARKER_EPOCH` (default `2026-08-19`). The fixture date is `2020-01-02`, far before that default.

## Decision

The test runs with `AUTODREAM_MARKER_EPOCH="$DATE"`, which makes the fixture date one whose report must carry the marker. Without it the marker-less report counts as a legacy report, the guard skips it, and the test would not exercise #111. The same epoch is set for the second run, which shows a complete report is still a no-op.

## Consequences

Dropping the variable makes the first half of the test fail for a reason unrelated to the guard's marker check, or pass against a guard that never looks at the marker. Keep the epoch equal to `DATE`, not later.
