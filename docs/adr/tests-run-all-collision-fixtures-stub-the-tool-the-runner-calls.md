# tests-run-all: collision tests stub `shasum` first on PATH and break one `grep` call at a time

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`collision_sandbox`, `run_dream_collision`, `test_collision_worklist_failure_aborts`, `test_collision_membership_probe_failure_aborts`, `test_persistent_sidecar_failure_counts_rows_not_attempts`)

## Context

A natural 48-bit hash collision cannot be produced in a test, so the hash is stubbed. Without a forced collision, every assertion in this family passes whether or not the collision handling works. That is what happened while the branch was patched across four review rounds. `run.sh` also appends its own fixed list to the caller's `PATH`, so a stub that is not first on `PATH` is never seen. The first version put the stub in a temp dir behind the system `shasum` and silently measured nothing.

## Decision

- `collision_sandbox` puts a constant-hash `shasum` in `$HOME/.local/bin`, and `run_dream_collision` puts that directory first on `PATH`.
- Each failure test installs a `grep` wrapper in the same directory. It exits 2 on one argv shape and execs `/usr/bin/grep` otherwise. The three call sites are separate: `-vxF` is the worklist rewrite, `-qxF` is the membership probe, and `-v` followed by a `^...` pattern is the sidecar rewrite. Failing one while the others work shows which guard fails closed.
- The membership-probe test exists because an earlier fixture failed only the `-vxF` rewrite. Reverting the probe to `|| continue` then left the suite green: a fail-open on the way into a check that fails closed on the way out.
- The sidecar-rewrite test counts rows, not attempts. One provenance row stays stale, and counting attempts reported 3 for it: one at detection plus the same hash seen once per dropped path.

## Consequences

A new `grep` flag used in the collision path needs its own shim case. A stub left behind the system tool on `PATH` makes these tests pass without testing anything.
