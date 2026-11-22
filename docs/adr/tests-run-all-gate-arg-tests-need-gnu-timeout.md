# tests-run-all: the oversized-gate argument tests resolve a GNU timeout and fail loudly without one

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_oversized_gate_script_args`)

## Context

`oversized-gate.sh --days` with no value left `$#` at 1 while `shift 2` refused to shift, so the script looped forever (found in review). A hang in a script next to the nightly is worse than a wrong number. The test has to bound each call, and stock macOS has no `timeout`. Homebrew coreutils installs `gtimeout`, and `timeout` too if its gnubin is on `PATH`.

## Decision

The test uses whichever of `timeout` or `gtimeout` exists. When neither does, it records a failure that names the missing tool and returns. These are the only assertions in the suite that need GNU `timeout`.

## Consequences

Without the resolution step, all four assertions return exit 127 and read as regressions in the script. A passing run needs exit 2, and exit 124 means the hang is back.
