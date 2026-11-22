# runsh: citation integrity is appended to run-stats after L2, and is never fatal

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `CITECHECK`, `citations_*`)

## Context
The run-stats keys are written BEFORE L2 runs, and this check needs the finished report. Appending keeps one self-audit artifact to read in the morning instead of a second sidecar. A citation defect is a measurement, and the report still ships.

## Decision
When `citation-check.sh` is executable, its output is appended to `run-stats.txt` after the pins step and before `notify.sh`; unresolved or to-gated citations log a WARNING (all resolved logs a plain line); a checker that could not run (missing jq, unreadable inputs) records `citations_total`, `citations_unresolved` and `citations_to_gated` as `unmeasured`, because absent keys would read as an older runner that predates the stat (see `runstats-keys-never-read-as-clean-zero`).

## Consequences
Do not move the check into the pre-L2 stats block, and do not make a citation defect fail the run.
