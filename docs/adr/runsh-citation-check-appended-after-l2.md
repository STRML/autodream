# runsh: citation integrity is appended to run-stats after L2, and is never fatal

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `CITECHECK`, `citations_*`)

## Context
The run-stats keys are written BEFORE L2 runs, and this check needs the finished report. Appending keeps one self-audit artifact to read in the morning instead of a second sidecar. A citation defect is a measurement, and the report still ships.

## Decision
`CITECHECK` output is appended to `run-stats.txt`; unresolved or to-gated citations log a WARNING; a checker that could not run records the three keys as `unmeasured` (see `runstats-keys-never-read-as-clean-zero`).

## Consequences
Do not move the check into the pre-L2 stats block, and do not make a citation defect fail the run.
