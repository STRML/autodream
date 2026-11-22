# runsh: a report is complete when it carries the end marker, never merely when its path is non-empty

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_complete`), `bin/report-format.sh` (`report_finishes`)

## Context

`-s` cannot tell a finished report from one the aggregator was killed halfway through writing; a truncated report satisfies it as well as a good one. That mattered three ways: the L2 retry loop would break after attempt 1 on a partial file, the superseded good copy would be deleted, and the consume gate would archive the user's notes and stamp bookmarks read against a half-written report. Mid-write death is exactly the sleep-kill scenario the retry machinery exists for. The marker (`<!-- autodream:open-questions=N -->`) closes the Open questions section, which is the last section PROMPT.md has L2 write, so its presence means the write reached the end. (The original comment called it the last thing PROMPT.md emits; the stdout grammar since added `AUTODREAM_REPORT_END`, which the runner strips before the report is stored.) See CLAUDE.md, "Sleep resilience" and "Operator notes".

## Decision

`report_complete` calls `report_finishes "$REPORT_PATH" "$TARGET_DATE"`, which needs a non-empty file, the open-questions marker, and (for dates from the questions epoch) the questions block. It deliberately does NOT use `L2_RC -eq 0`: the CLI can exit non-zero after a perfectly good write. The live gate (`report_complete`), the abandoned-date sweep (`unassembled_dates`) and the pin sweep (`sweep_stranded_pins`) all end in `report_finishes`, so they cannot disagree about whether a date is finished. The idempotency guard's `report_finishes_date` adds one allowance: a report from before `AUTODREAM_MARKER_EPOCH` (default 2026-08-19) counts as finished without a marker.

## Consequences

Do not weaken the gate to a size test or an exit code. A new consumer of "is the report done" must call `report_finishes`.
