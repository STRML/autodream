# tests-portable: expectations are literals, and the no-timeout fallback is forced by a stripped PATH in a fresh bash

Status: accepted · Date: 2026-11-22 · Code: `tests/portable.sh` (the `tmo` cases using `$nt`)

## Context

`bin/portable.sh` has a BSD branch and a GNU branch for the same helpers. If the expected value in a test comes from another `date` call, a branch that drifts passes on the OS whose `date` the test copies. CI runs the suite on Linux with every push, and on macOS whenever `portable.sh` changes, which is what exercises the other branch.

With no `timeout` binary, `tmo` backgrounds the command, and bash hands a background job `/dev/null` as stdin unless it is redirected explicitly. That fallback only runs on a host with no `timeout`, which Linux CI does have.

## Decision

- Expected values are literals worked out by hand, so a drifting branch fails whichever OS runs the suite.
- A directory holding symlinks to only `cat`, `sleep`, `kill` and `pkill` becomes `PATH`. That forces the fallback on any host, Linux CI included.
- The fallback cases run in a fresh `/bin/bash -c`. The test shell has already hashed `timeout`'s path, and `command -v` would answer from that hash.

## Consequences

Do not compute an expectation with the helper's own tool. Do not run the fallback cases in the test's own shell: they would silently exercise the `timeout` branch.
