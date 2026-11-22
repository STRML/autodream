# runsh: Each L1 engine call writes only its own staging dir under an OS sandbox, and the runner copies the answer out

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_setup`, `L1_CONFINED` and related globals)

## Context
Issue #169. An L1 worker holds the Write tool, so it could write any path the user can. No marker in the findings dir can tell the runner's writes from a worker's, so the access had to change.

## Decision
Each engine call gets its own staging directory (`$AUTODREAM_DIR/staging/run-<pid>/...`), writes its answer there, and runs under an OS sandbox that can write only that directory and the narrow state paths the engine itself needs (the adapter verb `l1-writes`); the runner copies the answer into the findings dir after the engine has exited. Staging happens whether or not the sandbox does, so the copy is one code path. A host with no working sandbox runs the workers as before and says so in run-stats (`l1_confined: no`, with the reason); the probe checks that a write beside the staging directory is refused, so a tool that accepts a profile and confines nothing counts as no sandbox.

Setup details:
- A run killed mid-flight leaves its staging root behind. Only roots whose run is gone (`kill -0` fails) are removed, because the nightly and an `autodream-now` run for another date are alive at once.
- When every session already has findings, no worker starts and there is nothing to confine or prepare. Every engine is named in `L1_SETUP_SKIPPED`, so a findings file that vanishes before dispatch fails the attempt (`l1_attempt`) and does not start an unprepared worker with no sandbox.
- The protected directories (`$AUTODREAM_DIR`, `$FINDINGS_DIR`, `$DREAMS_DIR`) are joined with a colon, so one that holds a colon would be split into two paths and left unprotected, and a relative one protects nothing. Either is an `L1_CONFINE_FATAL`.

Setup sets globals and is never called inside `$(...)`.

See CLAUDE.md, "Who starts the L1 worker" (A worker writes only its staging directory (#169); What the sandbox allows; A host with no working sandbox says so).

## Consequences
Unverified: a token refresh inside the sandbox (see CLAUDE.md). `tests/l1-confine-real.sh` is the manual check. The confinement tests skip where `sandbox-exec` cannot start.
