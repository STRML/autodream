# tests-run-all: the runner-provenance fixtures copy the installed symlink layout, use physical paths, and stay under the hop cap

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_runner_provenance_through_symlink`, `test_runner_provenance_relative_symlink`, `test_runner_provenance_unresolvable_chain`, `test_runner_dirty_ignores_untracked`)

## Context

`run-stats.txt` records `runner_commit` and `runner_dirty` (#29). The runner finds its checkout by following its own symlink. `bin/run.sh` caps the walk at 8 hops, because macOS refuses to execute anything behind 16 or more links (ELOOP), so a cap at or above 16 could never fire.

## Decision

- The symlink test builds what `install.sh` leaves on disk: a real directory holding one symlink per script, not a link to the checkout. `cd "$(dirname "$0")"` then lands in a directory with no `.git`, and provenance has to follow the file's own link. Six production runs through 2026-08-03 stamped `unknown` against a clean checkout because earlier tests missed this.
- The relative-target test exists because `install.sh` writes absolute targets, so production never exercises the relative branch. Both sides go through `pwd -P` before `relpath`. `$TMPDIR` on macOS sits under `/var`, itself a link to `/private/var`, and a relative path computed from the logical name walks up through a directory that does not exist, so the link is born broken.
- The chain test uses 12 hops: above the cap of 8, below 16, so bash still runs the script and only the provenance field degrades. A truncated walk must say `unknown`, never stamp the sha of whatever checkout the truncated path sits in (here, this repo).
- `runner_dirty` counts tracked modifications only (`git status --porcelain --untracked-files=no`). A clean checkout with a stray untracked file reported `runner_dirty: yes` on the first production run. Untracked files are not code that exists in nobody's history.

## Consequences

A chain of 16 or more hops fails to execute on macOS and tests nothing. Using logical paths in the relative fixture can pass on Linux and break on macOS.
