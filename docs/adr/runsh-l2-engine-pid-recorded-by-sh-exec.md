# runsh: the L2 engine is started through a one-line sh that records its pid and then execs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `L2_PIDFILE`, `/bin/sh -c 'printf %s "$$" > "$0"; exec "$@"'`; `l2_diag_start`, `l2_diag_end`)

## Context
Issue 42: L2 attempt 1 died with exit 143 on 2026-08-01, 08-31, 09-02, 09-04, 09-19 and 10-02 with no record of who sent the signal (see the `L2 attempt diagnostics (issue 42)` comment above `l2_diag_start`). `run.sh` applies no timeout of its own to L2, so the TERM comes from outside. When an attempt exits 143, 137 or 124, `l2_diag_end` writes `findings/<date>/l2-attempt-N.diag` (see `l2-attempt-diagnostics-are-evidence-only`). The diagnostics need the engine's own pid, not a wrapper's.

## Decision
The engine starts through `/bin/sh -c 'printf %s "$$" > "$0" ...; exec "$@"'`, so the pid in the diagnostics is the engine's. `exec` keeps the pid, stdin and argv. If the pid file cannot be made (`mktemp` fails), `L2_PIDFILE` is `/dev/null` and the diagnostics have no pid to read.

## Consequences
Do not insert a wrapper process between the sh and the engine; the diag file would name the wrong pid.
