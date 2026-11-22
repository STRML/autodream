# runsh: the L2 engine is started through a one-line sh that records its pid and then execs

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `L2_PIDFILE`, `/bin/sh -c 'printf %s "$$" > "$0"; exec "$@"'`; `l2_diag_start`, `l2_diag_end`)

## Context
Issue 42: L2 attempt 1 died with exit 143 on 2026-08-01, 08-31, 09-02, 09-04, 09-19 and 10-02 with no record of who sent the signal (see the `L2 attempt diagnostics (issue 42)` comment above `l2_diag_start`). The diagnostics need the engine's own pid, not a wrapper's.

## Decision
The engine starts through `/bin/sh -c 'printf %s "$$" > "$0" ...; exec "$@"'`, so the pid in the diagnostics is the engine's. `exec` keeps the pid, stdin and argv.

## Consequences
Do not insert a wrapper process between the sh and the engine; the diag file would name the wrong pid.
