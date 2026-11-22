# runsh: every FATAL funnels through log_fatal and fatal_exit, which leave a marker AND post a banner, never a stub report

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`FATAL_REASON`, `log_fatal`, `fatal_exit`, `notify_fatal`)

## Context
A run that dies writes no report and posts no banner; until `fatal_exit` existed a failed night was completely silent (the log line was the only record, and nothing reads the log). The marker and the banner cover different failures: a transient cause is caught by the marker when a later night succeeds, while a persistent one (a lost exec bit, jq off the launchd PATH) never has a later success to be read by, so it needs the banner tonight.

## Decision
- `log_fatal` records the reason in `FATAL_REASON` so it survives to the exit path.
- `fatal_exit` writes the five-line `run-stats.txt` (`runner_commit`, `runner_dirty`, `fatal`, `sessions_triaged: 0`, remote-sync lines) and calls `notify_fatal`. It is deliberately NOT a stub report: a report is what the idempotency guard reads as "this date is complete", and it is not.
- NEVER over a date that already has a report. `AUTODREAM_FORCE` bypasses the idempotency guard by design (the documented `autodream-now.sh <date> --force` path), so any fatal under it would otherwise overwrite that date's full L1/L2 telemetry with the stub and announce a FAILED night while `dreams/<date>.md` sits there complete; `unassembled_dates()` would not catch it because the report exists.
- The guard covers the WRITE only. The first version returned before the banner too, and that branch is reachable in exactly one situation, the detached `--force` rebuild under launchd, where the banner is the only surface an operator sees: with no banner the operator polls `dreams/<date>.md`, finds the OLD report, and reads a failed rebuild as a successful one. So the guarded branch still calls `notify_fatal`, with the note that the existing report is unchanged.
- Both fatal paths post through `notify_fatal`, so the posting lives in one place. Keeping two copies is how the guarded path lost its banner in the first place.

## Consequences
A new fatal must go through `log_fatal` and the `fatal_exit` exit, not `exit 1` after a bare echo (the pre-log startup FATALs are the exception: the log does not exist yet).
