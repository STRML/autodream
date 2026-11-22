# runsh: L2 attempt diagnostics are bounded evidence gathered off the critical path, and nothing depends on them

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l2_diag_probe`, `l2_diag_start`, `l2_diag_start_body`, `l2_diag_collect`, `l2_diag_end`)

## Context

Issue 42. L2 attempt 1 has died with exit 143 (SIGTERM) and a bare "Execution error" on 2026-08-01, 08-31, 09-02, 09-04, 09-19 and 10-02, and nothing in the log says who sent the signal. `run.sh` applies no timeout of its own to L2, so the TERM comes from outside.

## Decision

When an attempt exits 143, 137 or 124, `l2_diag_end` writes `findings/<date>/l2-attempt-N.diag`: timestamps, the exit code, the worker's pid and parent chain, the launchd job's state, load, memory pressure, the kernel's last sleep and wake times, and the other autodream or claude processes. Every probe runs bounded (3 s) in its own background job and cannot fail the run: a hung `launchctl` costs three seconds, a missing tool costs one line. `l2_diag_probe` output is cut by line (`cut -c1-600 | head -n 80`), so a huge command line cannot cut the output mid-line and glue the next heading to it. The start half is gathered by a background job (`l2_diag_start`, `l2_diag_start_body`), so an attempt that goes on to succeed, nearly all of them and every one in the test suite, pays nothing for it; `l2_diag_end` collects it through `l2_diag_collect` (waiting up to 3 s for the job), and on any other exit code discards it. Both calls in the L2 loop are `|| true`.

## Consequences

No behaviour may depend on any of it. Do not make a probe unbounded, and do not run the start half in the foreground. The source of the SIGTERM is still unnamed.
