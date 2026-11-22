# runsh: only a sentinel-validated, marker-bearing L2 capture counts as a delivered report

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `L2_ATTEMPTED`, `L2_DELIVERED`, `L2_SENTINEL`, `report_has_sentinel`, `report_body`, `report_complete`, the final `return`)

## Context
- `L2_ATTEMPTED` separates a fresh run that actually spawned the aggregator from the legacy short-circuits (the idempotency guard and the COUNT=0 stub both return before L2). `L2_DELIVERED` flips to 1 only when an attempt's capture carried the `AUTODREAM_REPORT_END` sentinel. Both default to 0 so the move-aside can tell "this run confirmed delivery" from "this run never reached L2": a marker-bearing report left by an earlier night must not be read as this run's output.
- The sentinel is the completion gate: everything before the LAST occurrence is the report body, and a capture without one is a degraded report whether or not it has the open-questions marker, because the marker alone cannot prove the output reached the end. Both writes are staged to a `.tmp` and renamed so a half-staged file never lands at `$REPORT_PATH`. Lines after the sentinel (pin block, report path, summary) are appended to the run log so a stripped capture never loses them.
- The loop breaks only on a sentinel-validated capture that also carries the marker; a degraded capture never satisfies it.
- Only a sentinel-validated report counts as delivered; a degraded capture that could not be moved aside also leaves a file at the path and must not be reported as ready.
- The exit status is the same predicate the move-aside and consume gates use (`L2_DELIVERED` and `report_complete`). A degraded night can leave the aggregator's own exit code at 0, which would tell the launchd job (the only watcher an unattended run has) that the night produced a usable report when it produced none. Anything short of validated keeps the aggregator's non-zero status, else 1.

## Decision
As above. See CLAUDE.md, "L2 is read-only: the report and the pins arrive on stdout" (grammar, "Delivery means a capture with the sentinel").

## Consequences
Weakening any one of these to `-s "$REPORT_PATH"` or marker-only re-opens silent data loss. `AUTODREAM_REPORT_END` is part of `L2_SYSTEM.txt` and `bin/report-format.sh`; change them together.
