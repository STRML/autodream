# runsh: The count of already-valid findings is recorded before any worker runs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `L1_PRECACHED`)

## Context
Without it, a re-run after a partial crash shows an "impossible" `l1_elapsed_seconds` (for example 2s for 36 sessions), because the dispatcher's idempotent skip exits every worker instantly. The aggregator's self-audit needs the count to tell "fast run" from "broken timer".

## Decision
Before any worker runs, `L1_PRECACHED = COUNT - l1_missing_count`, the sessions in the worklist that already have a valid findings JSON. It feeds `l1_sessions_already_done_at_start` and `l1_sessions_freshly_processed`.

## Consequences
- Measure it before the first dispatch; after it the number is the run's own output.
