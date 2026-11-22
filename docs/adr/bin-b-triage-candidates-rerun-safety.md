# bin-b: a rerun of a report date neither keeps the old list nor is held back by its own suggestion

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-candidates.sh` (`held_back`, `last_suggestion`, the artifact removal before the first exit)

## Context

The nightly can be retried, and a date can be rebuilt long afterward. A stale `triage-candidates.md` from an earlier run would be copied by L2 into the new report, and a retried night held back by its own earlier suggestion would show nothing.

## Decision

- Both output files are removed before the first early exit, whatever happens next.
- The cooldown counts from the report date (the findings directory's name), not from today, so a late rerun of an old night judges it as that night did. A negative gap (a rerun of an older night, or a skewed clock) applies no cooldown, and a state row for the same date is a retried night and never holds it back.
- `last_suggestion` takes the latest valid row for the slug, compared in any case, so one garbage row cannot hide a good one.

## Consequences

Keep the state file's `slug<TAB>date<TAB>count` shape. `record_suggestion` skips a row identical to the last, so reruns do not grow it.
