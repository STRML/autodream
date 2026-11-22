# runsh: a report is complete when it carries the end marker, never merely when its path is non-empty

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`report_complete`), `bin/report-format.sh` (`report_finishes`)

## Context

`-s` cannot tell a finished report from one the aggregator was killed halfway through writing; a truncated report satisfies it as well as a good one. That mattered three ways: the L2 retry loop would break after attempt 1 on a partial file, the superseded good copy would be deleted, and the consume gate would archive the user's notes and stamp bookmarks read against a half-written report. Mid-write death is exactly the sleep-kill scenario the retry machinery exists for. The marker is the last thing PROMPT.md emits, so its presence means the write reached the end. See CLAUDE.md, "Sleep resilience" and "Operator notes".

## Decision

`report_complete` calls `report_finishes "$REPORT_PATH" "$TARGET_DATE"`, which needs a non-empty file, the open-questions marker, and (for dates from the questions epoch) the questions block. It deliberately does NOT use `L2_RC -eq 0`: the CLI can exit non-zero after a perfectly good write. The live gate, the abandoned-date sweep (`unassembled_dates`) and the pin sweep all call the same function, so they cannot disagree about whether a date is finished.

## Consequences

Do not weaken the gate to a size test or an exit code. A new consumer of "is the report done" must call `report_finishes`.
