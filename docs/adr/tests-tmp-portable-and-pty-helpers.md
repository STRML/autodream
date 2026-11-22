# tests: tmp-portable-and-pty-helpers: tmp, portable and pty test helpers

Status: accepted · Date: 2026-11-22 · Code: `tests/lib-tmp.sh` (`suite_tmp`), `tests/tmp-cleanup.sh` (`interrupt_suite`), `tests/notes-path.sh`, `tests/portable.sh` (the `tmo` cases using `$nt`), `tests/with-pty.py` (`main`)

## a suite owns one temp root removed on every exit path, and the interrupt check must hit a suite that is still running

### Context

A suite that makes temp dirs with `mktemp -d` and removes them on its last line leaks them on Ctrl-C, a harness timeout or an early exit (issue #63). macOS never collects a non-empty tree under `/tmp`: `com.apple.tmp_cleaner` takes only empty directories older than three days.

- bash runs an EXIT trap on a trapped signal only if the handler exits, so INT and TERM exit with 130 and 143. The EXIT trap itself does not call `exit`, so it cannot flip a red suite green. A trap is right in a test suite and wrong in `adapters/claude/adapter.sh`, which must die promptly on SIGTERM (issue #57).
- macOS and GitHub's runners set `TMPDIR` with a trailing slash and `mktemp` keeps the `//`. A suite that compares a path with what `cd && pwd` prints (`tests/notes-path.sh`) failed on the string in CI and passed locally.
- A signal landing after `mktemp` creates the directory and before `SUITE_TMP` is assigned leaks it. The window is microseconds wide and bash cannot close it without blocking signals.

### Decision

- `suite_tmp NAME` arms the traps first (`${SUITE_TMP:-}` keeps cleanup a no-op until set), strips the trailing slash from `TMPDIR`, makes one directory and exports it as `TMPDIR`, so a `mktemp -d` inside `$(...)` lands inside it too.
- `tmp-cleanup.sh` starts each suite in its own process group under a private `TMPDIR` and TERMs the group once an entry exists two levels deep, which means `suite_tmp` has returned and the signal cannot land in the residual window. A suite that is already gone when the signal arrives FAILS the case: an uninterrupted run that cleaned up on its last line proves nothing. A very fast suite (preflight takes tens of ms) gets up to five tries.
- `run-all` is started with `RUNALL_SHARD` and `RUNALL_LIST` unset, since it is the suite under interruption and not a slice of one.

### Consequences

Never turn "already gone" into a pass. `notes-path.sh` strips the slash itself because it builds its sandbox before it can source this library.

## expectations are literals, and the no-timeout fallback is forced by a stripped PATH in a fresh bash

### Context

`bin/portable.sh` has a BSD branch and a GNU branch for the same helpers. If the expected value in a test comes from another `date` call, a branch that drifts passes on the OS whose `date` the test copies. CI runs the suite on Linux with every push, and on macOS whenever `portable.sh` changes, which is what exercises the other branch.

With no `timeout` binary, `tmo` backgrounds the command, and bash hands a background job `/dev/null` as stdin unless it is redirected explicitly. That fallback only runs on a host with no `timeout`, which Linux CI does have.

### Decision

- Expected values are literals worked out by hand, so a drifting branch fails whichever OS runs the suite.
- A directory holding symlinks to only `cat`, `sleep`, `kill` and `pkill` becomes `PATH`. That forces the fallback on any host, Linux CI included.
- The fallback cases run in a fresh `/bin/bash -c`. The test shell has already hashed `timeout`'s path, and `command -v` would answer from that hash.

### Consequences

Do not compute an expectation with the helper's own tool. Do not run the fallback cases in the test's own shell: they would silently exercise the `timeout` branch.

## the pty wrapper sends one best-effort end-of-file and reports exec failure plainly

### Context

`with-pty.py` runs a command with a pseudo-terminal as its stdin, stdout and stderr, whatever the caller's own are. BSD `script -q /dev/null cmd` does the same job but calls `tcgetattr` on its own stdin and dies with "Operation not supported on socket" when handed a socket or a closed descriptor.

- In the child after `pty.fork`, stderr is the pty. An exec failure printed as a traceback would arrive in the test's output as terminal noise.
- A program that reads its terminal would otherwise wait forever for input.
- The newline and `^D` are written in canonical mode, once the child has had time to exec. A program that flushes its terminal input after that point (readline does) discards them, and one that reads its terminal would then wait.

### Decision

- An `OSError` from `execvp` prints `with-pty: cannot run <cmd>: <reason>` and exits 127, the shell's status for a command that cannot be run.
- After a 0.2 second sleep the parent writes `"\n\x04"` to the master. The newline completes a line and `^D` at the start of a line is end-of-file. A write error means the child already exited and is ignored.
- Output is copied to the parent's stdout until EIO and the exit status is the child's.

### Consequences

The EOF is best effort and covers the commands the suite runs. A command that flushes terminal input needs another way to be driven.
