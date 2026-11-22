# runsh: the changelog source loop runs in the current shell and its first-error variable is a dynamically scoped local

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_window`, `changelog_fail`, `changelog_warn_all_failed`)

## Context

The loop sets counters (`sources`, `failed`), and `changelog_fail` sets `CHANGELOG_FIRST_ERR`, all of which are read after the loop. A piped `while read` runs in a subshell and loses them.

## Decision

The loop reads from a here-string (`<<< "$srcs"`), not a pipe. `CHANGELOG_FIRST_ERR` is declared `local` in `changelog_window` and is seen by `changelog_fail` and `changelog_warn_all_failed` through bash's dynamic scoping, so it never outlives the run's one changelog pass.

## Consequences

Do not pipe into this loop, and do not make `CHANGELOG_FIRST_ERR` global. A function that sets it must be called from inside `changelog_window`.
