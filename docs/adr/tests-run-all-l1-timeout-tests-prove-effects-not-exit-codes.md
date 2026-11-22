# tests-run-all: the L1 timeout tests prove the effect (group reaped, elapsed time, zero refused), not an exit code

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_l1_hang_is_bounded`, `test_intrinsic_124_is_not_a_timeout`, `test_l1_timeout_must_be_positive`, `test_l1_warmup_timeout_must_be_positive`)

## Context

The 2026-08-19 and 2026-08-22 runs each sat for days with every `xargs -P` slot held by a worker that never exited. No error, no report, and launchd would not start a replacement while the label was still running, so the catch-up triggers were suppressed too.

- A kill aimed at the worker alone leaves its children alive and reparented to init; 57 `node_repl` and `mnemopi_embed` orphans accumulated on the real host that way. `kill -0` also succeeds on a zombie, and a child whose parent just died is one until init reaps it, so one immediate check fails a correct kill on timing alone.
- GNU `timeout` propagates the child's exit status, so a worker that exits 124 by itself, or is SIGKILLed by the OOM killer, looks identical to a fired deadline. Only elapsed time separates them, and it must be measured from the launch of `timeout`, not the top of the worker, or preprocessing time closes the gap on a short bound.
- GNU `timeout` reads 0 as "no timeout", so an unvalidated 0 restores the wedge while the startup log still claims a bound.

## Decision

- The hang test records the mock child's pid, then gives each pid a bounded grace (10 x 0.5 s) before counting it leaked.
- The intrinsic-124 test uses a 900 s bound and asserts `l1_timed_out: 0` and no timeout line in the `.err`.
- Zero and non-numeric values for `AUTODREAM_L1_TIMEOUT` and `AUTODREAM_L1_WARMUP_TIMEOUT` are refused at startup and no report is written.

## Consequences

Replacing the grace loop with a single `kill -0` makes the hang test flaky. Asserting only the exit status cannot tell a real deadline from an intrinsic 124. See CLAUDE.md "A hung worker, a cold token and a deterministic failure".
