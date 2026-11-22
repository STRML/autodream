# runsh: a finished report makes later triggers cheap no-ops (the idempotency guard)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, `report_finishes_date`)

## Context
Sleep resilience relies on several wake-time launchd triggers per morning. A run that failed overnight left no report and must proceed; once the night succeeded the later triggers must cost nothing.

## Decision
A report is only written after a successful L2 and carries the open-questions marker when whole, so a report that `report_finishes_date` accepts means the date is complete. `report_finishes_date` plus `AUTODREAM_FORCE != 1` logs `report already exists ... nothing to do`, records a `noop` outcome and returns 0 (`AUTODREAM_FORCE=1` rebuilds). A failed overnight run left no report, so it proceeds and finishes the work. A non-empty report that fails the check (no marker) logs `lacks the open-questions marker; treating <date> as unfinished and rebuilding it` and proceeds; the move-aside before L2 sets it aside as `.stale-<epoch>`, keeps it if the rebuild fails and discards it once a complete report replaces it.

## Consequences
See CLAUDE.md, "Sleep resilience" (idempotency guard; a marker-less report is moved aside and rebuilt, #111).
