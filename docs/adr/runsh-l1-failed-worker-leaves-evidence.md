# runsh: a failed L1 worker keeps its stdout, exit code and elapsed time as evidence

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body: `outlog`, `l1_attempt`)

## Context
The worker printed its whole diagnosis to stdout and that used to go to `/dev/null`, so every failure looked the same: an `.err` holding the single line "Working..." and a hand-written sentence from the runner. On 2026-09-04 (omp-autodream) a dead network hid behind three fine transcripts and the report blamed their size. Without the exit code a provider refusal and a killed process read identically.

## Decision
Each engine call writes stdout to its `$4` and stderr to its `$3`: `<hash>.json.out` and `<hash>.json.err` for a whole session, `NN.out` and `NN.err` under `.chunks/<hash>/` for a chunk. When the call produces no findings JSON, `l1_attempt` appends to the `.err` the diagnostic line, `worker exit code: <rc> after <n>s`, and the last 40 lines of stdout under `--- worker stdout, last 40 lines ---` (or `worker stdout was empty`), then removes the `.out`, whose tail is now in the `.err`. An answer that exists but fails the validity check is treated as a failure too: the `.err` gets `worker wrote output with no usable .findings key; treating as a failure` and the first 2000 bytes of what was written, and the file is removed. The `.err` survives every failure and is deleted only when the worker succeeds (a chunk's `.err` and `.out` likewise).

## Consequences
The original comment said the `.out` is kept when the worker fails; the code removes it once its tail is in the `.err`, so the `.err` is the only evidence file left. `bin/failure-class.sh` reads these lines by exact text, so changing their wording changes failure classification. See CLAUDE.md, "A failed worker leaves its evidence, and the failure is classified".
