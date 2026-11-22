# runsh: Preflight runs below the idempotency guard, above enumeration, through bash, and owns the dependency checks

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the preflight block after the report-already-exists guard)

## Context
- With `shasum` absent, the artifact hash assignment yields an empty string and every session in the night writes to the same findings filename. A run that got that far would produce one record where it should have produced a hundred and report success. Stopping before enumeration costs a night; continuing corrupts one.
- Above the idempotency guard, a host missing one dependency turned an already-complete date from a one-second no-op into a failed run and an exit 1 on each of the four morning triggers.
- `install.sh`'s own comment worries about a distribution path that loses the exec bit (a zip, a restrictive umask). An `[ -x ]` gate answers that by skipping the check silently, which lands back in the empty-hash corruption preflight exists to stop.
- An earlier commit moved a `[ -x "$CLAUDE_BIN" ]` test to this spot, and its message claimed that made preflight's `--l2-bin` branch reachable. It did not: the `[ -x ]` test still ran first, and for an absolute path (the `CLAUDE_BIN` default) `command -v` cannot fail once `[ -x ]` has passed, so the `l2_engine` branch stayed exercised only by its own test suite. Two gates for one dependency, the second one dead.
- `L2_BIN` was always empty before `--l2-bin` was passed, so preflight's `l2_engine` check could only fire from its own test suite: a dependency gate with a branch production never reached.

## Decision
- `run` checks no `claude` binary itself. Preflight owns it, so the check that reports the failure is the one that fires.
- Preflight runs after the "report already exists" guard and before `scan_roots`/enumeration.
- It is gated on `-r "$PREFLIGHT"` and invoked as `bash "$PREFLIGHT" --l2-bin "$CLAUDE_BIN"`, not gated on `-x`. A present-but-unreadable preflight logs `WARNING: preflight not readable ...; the shared-dependency check did NOT run`.
- A preflight failure is `log_fatal`, `fatal_exit`, return 1, "Nothing was enumerated."

## Consequences
- Do not re-add a `[ -x "$CLAUDE_BIN" ]` check above preflight, and do not gate preflight on `-x`.
- Moving preflight above the idempotency guard makes a missing dependency fail finished dates on every catch-up trigger.
- Moving it below enumeration lets the empty-hash corruption write a record for the night.
- Dropping `--l2-bin` makes the `l2_engine` check unreachable in production again.
