# runsh: every L1 worker runs under GNU timeout without --foreground, so the whole process group is signalled

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`AUTODREAM_L1_TIMEOUT`, `L1_KILL_GRACE`, `TIMEOUT_BIN`; the `l1wrap` prefix in `dispatch_l1`)

## Context
A worker that never exits holds its `xargs -P` slot forever, so FANOUT hung workers stop the whole run with no error and no report. 2026-08-19 and 2026-08-22 each sat wedged for days with all 8 slots taken by workers blocked on their own `node_repl` and `mnemopi_embed` children (omp-autodream).

## Decision
`dispatch_l1` prefixes the engine with `timeout -k "$L1_KILL_GRACE" "$AUTODREAM_L1_TIMEOUT"` (defaults 1200 s and 30 s). GNU timeout invoked WITHOUT `--foreground` runs the command in a new process group and signals the group, which reaps the grandchildren; a bare kill on the engine would leave them reparented (to launchd on macOS) and running. The worst-case bound is `AUTODREAM_L1_TIMEOUT + L1_KILL_GRACE`. macOS ships no `timeout` in its base install, so with none on PATH (`TIMEOUT_BIN` is resolved after the PATH augmentation) the run degrades to unbounded instead of gaining a hard coreutils dependency, and run-stats records which way it went (`l1_timeout_bin`). See CLAUDE.md, "A hung worker, a cold token and a deterministic failure".

## Consequences
Never add `--foreground`: it stops signalling the group and the grandchildren survive. The unbounded fallback is deliberate and visible only in run-stats. Startup validation of the knob is in `numeric-knobs-validated-at-startup`.
