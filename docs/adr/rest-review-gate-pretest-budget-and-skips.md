# rest: the review-gate pretest runs the unit suites inside a fixed budget and says what it skipped

Status: accepted · Date: 2026-10-05 · Code: `.review-gate/pretest`

## Context

The review gate (`~/.claude/scripts/review-gate-lib.sh`, `rg_pretest`) runs this script before a review round, outside the headless lane's classifier, and inlines the output into the review prompt, which keeps only the last 150 lines. The block a reviewer reads is therefore the `PRETEST SUMMARY` at the end. The harness kills the script at 900 seconds.

`tests/run-all.sh` takes over 10 minutes, so it cannot run here; it is run by hand before merging a `run.sh` change. Mocks and `replay.sh` (needs arguments) are not suites.

`tests/adapter-claude.sh` needs a usable `ps` and `tests/review-cmux.sh` needs a pty. The Claude Code sandbox denies both, and both pass outside it.

## Decision

The script runs every `tests/*.sh` except `mock-*`, `replay.sh` and `run-all.sh`, with a total budget of 800 seconds and at most 120 seconds per suite. A suite past its cap is marked `TIMEOUT` and the rest still run. Suites left when the budget is spent are listed as `NOT RUN`.

The two environment-bound suites are probed for the capability they need (`can_ps`, `can_pty`) and not for the sandbox, so they run wherever the capability exists and are listed as `skipped` otherwise. `can_ps` is the same test as `ps_usable` in `tests/adapter-claude.sh`.

## Consequences

A skipped suite did not run in the review lane, and the summary line says each passes outside the sandbox. If the suite count grows past the budget, the tail silently moves to `NOT RUN`, so watch that line. Changing the 800 and 900 numbers means changing the harness timeout too.
