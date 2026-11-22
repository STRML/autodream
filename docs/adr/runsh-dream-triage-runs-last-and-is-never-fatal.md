# runsh: dream triage is opt-in, runs last, and is never fatal

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `AUTODREAM_TRIAGE`, `TRIAGE_DREAM`, `bin/triage-dream.sh`)

## Context
It is one more model call, so a hang or a failure there must not hold back the pins, the banner or the consume steps above it. Only a validated delivery is triaged. The engine is L2's (an adapter); the model gets Read and Glob only, and `bin/triage-dream.sh` writes `dreams/<date>.triage.md` itself.

## Decision
When `AUTODREAM_TRIAGE=1`, `L2_DELIVERED=1` and `report_complete`, the runner calls the script with `AUTODREAM_L2_ENGINE="$L2_ENGINE"`, appends its output to the run log, logs and continues on failure, and cleans the work bucket. It is off unless `AUTODREAM_TRIAGE=1`, and a missing `triage-dream.sh` logs and skips.

## Consequences
Keep it last. Do not make the missing or failing script abort the run.
