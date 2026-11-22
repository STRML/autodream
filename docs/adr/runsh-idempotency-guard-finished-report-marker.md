# runsh: a finished report makes later triggers cheap no-ops (the idempotency guard)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, `report_finishes_date`)

## Context
Sleep resilience relies on several wake-time launchd triggers per morning. A run that failed overnight left no report and must proceed; once the night succeeded the later triggers must cost nothing.

## Decision
A report is only written after a successful L2 and carries the open-questions marker when whole. `report_finishes_date` plus `AUTODREAM_FORCE != 1` exits early with a `noop` outcome (`AUTODREAM_FORCE=1` rebuilds). A failed overnight run left no report, so it proceeds and finishes the work.

## Consequences
See CLAUDE.md, "Sleep resilience" (idempotency guard; a marker-less report is moved aside and rebuilt, #111).
