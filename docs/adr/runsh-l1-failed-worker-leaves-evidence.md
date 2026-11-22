# runsh: a failed L1 worker keeps its stdout, exit code and elapsed time as evidence

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body: `outlog`, `l1_attempt`)

## Context
The worker printed its whole diagnosis to stdout and that used to go to `/dev/null`, so every failure looked the same: an `.err` holding the single line "Working..." and a hand-written sentence from the runner. On 2026-09-04 (omp-autodream) a dead network hid behind three fine transcripts and the report blamed their size. Without the exit code a provider refusal and a killed process read identically.

## Decision
Each engine call writes stdout to `$output.out` and stderr to `$output.err`. When the call produces no findings JSON, `l1_attempt` appends to the `.err` the diagnostic line, `worker exit code: <rc> after <n>s`, and the last 40 lines of stdout (or `worker stdout was empty`). The `.err` and `.out` are deleted only when the worker succeeds.

## Consequences
`bin/failure-class.sh` reads these lines by exact text, so changing their wording changes failure classification. See CLAUDE.md, "A failed worker leaves its evidence, and the failure is classified".
