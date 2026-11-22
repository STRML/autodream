# tests-run-all: a fatal still posts a banner and leaves a marker, including under --force and a persistent cause

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_fatal_does_not_clobber_a_complete_date`, `test_no_usable_adapter_leaves_a_trace`)

## Context

`fatal_exit` truncates `run-stats.txt` and posts a FAILED banner. `AUTODREAM_FORCE` bypasses the idempotency guard by design (`autodream-now.sh <date> --force`), so a fatal there would overwrite a complete date's telemetry with a five-line stub. An earlier version of the test asserted the banner must not fire and passed, which is how the guard came to suppress it: the run-stats write is what must not clobber a complete date, and the banner was taken down with it by sitting inside the same `return`. That branch runs detached under launchd, where a silent death leaves the operator polling `dreams/<date>.md`, finding the old report and reading the failed rebuild as a success.

Losing the exec bit on `adapters/claude/adapter.sh` (tarball copy, restrictive umask, `core.fileMode=false`) makes `_adapter_ok` accept nothing and `run()` return about 600 lines before `notify.sh`, with no findings JSON and no run-stats. The cause repeats every night, so no later run ever succeeds to read a marker and report it.

## Decision

- Under `--force` a fatal leaves run-stats untouched but still calls `notify.sh --failure`, saying the standing report is the old one.
- A total adapter outage writes a `fatal:` marker, calls the banner (the surface that works tonight), and the next night's run names the dead date.
- The tests install a `notify.sh` stub that records its arguments, because `fatal_exit` gates on `-x` and without one the notification step is skipped and unobservable.
- The banner is matched with `'[-][-]failure'`. `assert_grep` passes the pattern straight to grep, so a literal `--failure` reads as end-of-options and an inserted `--` becomes the pattern, which is what the first version did.

## Consequences

Do not move the banner back inside the run-stats guard. CLAUDE.md, "Nobody was told (`unassembled_dates`)", has the related unassembled-date surface.
