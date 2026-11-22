# tests-tmp: a suite owns one temp root removed on every exit path, and the interrupt check must hit a suite that is still running

Status: accepted · Date: 2026-11-22 · Code: `tests/lib-tmp.sh` (`suite_tmp`), `tests/tmp-cleanup.sh` (`interrupt_suite`), `tests/notes-path.sh`

## Context

A suite that makes temp dirs with `mktemp -d` and removes them on its last line leaks them on Ctrl-C, a harness timeout or an early exit (issue #63). macOS never collects a non-empty tree under `/tmp`: `com.apple.tmp_cleaner` takes only empty directories older than three days.

- bash runs an EXIT trap on a trapped signal only if the handler exits, so INT and TERM exit with 130 and 143. The EXIT trap itself does not call `exit`, so it cannot flip a red suite green. A trap is right in a test suite and wrong in `adapters/claude/adapter.sh`, which must die promptly on SIGTERM (issue #57).
- macOS and GitHub's runners set `TMPDIR` with a trailing slash and `mktemp` keeps the `//`. A suite that compares a path with what `cd && pwd` prints (`tests/notes-path.sh`) failed on the string in CI and passed locally.
- A signal landing after `mktemp` creates the directory and before `SUITE_TMP` is assigned leaks it. The window is microseconds wide and bash cannot close it without blocking signals.

## Decision

- `suite_tmp NAME` arms the traps first (`${SUITE_TMP:-}` keeps cleanup a no-op until set), strips the trailing slash from `TMPDIR`, makes one directory and exports it as `TMPDIR`, so a `mktemp -d` inside `$(...)` lands inside it too.
- `tmp-cleanup.sh` starts each suite in its own process group under a private `TMPDIR` and TERMs the group once an entry exists two levels deep, which means `suite_tmp` has returned and the signal cannot land in the residual window. A suite that is already gone when the signal arrives FAILS the case: an uninterrupted run that cleaned up on its last line proves nothing. A very fast suite (preflight takes tens of ms) gets up to five tries.
- `run-all` is started with `RUNALL_SHARD` and `RUNALL_LIST` unset, since it is the suite under interruption and not a slice of one.

## Consequences

Never turn "already gone" into a pass. `notes-path.sh` strips the slash itself because it builds its sandbox before it can source this library.
