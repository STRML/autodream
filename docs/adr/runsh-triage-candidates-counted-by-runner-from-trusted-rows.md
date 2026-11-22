# runsh: repos worth triaging are counted by the runner from its own session rows

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `TRIAGE_CANDIDATES` step; `SESSION_ROWS`)

## Context
`triage-candidates.sh` counts untriaged open issues in the repos tonight's sessions ran in and writes `triage-candidates.md` for L2 to copy into the report. L2 has no shell or `gh`, so the runner does the counting. `SESSION_ROWS` was built before any model ran, so it is the runner's own list of working directories and not something a model could have rewritten.

## Decision
The runner pipes `SESSION_ROWS` into the script; a failure logs and the report is unaffected. See CLAUDE.md, "Where state lives" (`triage-candidates.{md,tsv}`).

## Consequences
Never feed the script cwds from a findings JSON or L1/L2 output. A stale list from an earlier run is removed before the step so L2 cannot copy it.
